param(
  [string]$OutputDirectory,
  # Also run the Windows App Certification Kit while the test certificate is
  # trusted. Its report is evidence only; it does not fail the smoke test.
  [switch]$RunAppCert,
  # After the zero-network check, drive the app through UI Automation with a
  # public test playlist and save Store listing screenshots. Evidence only.
  [switch]$CaptureScreenshots,
  [string]$ScreenshotPlaylist = 'https://klipa.tv/tools/api/sample-m3u'
)

# Installs a test-signed COPY of the Store MSIX, launches it through its
# package identity, checks a clean zero-network start, and removes it again.
# Meant for a disposable CI runner: it trusts a throwaway certificate on the
# machine for the length of the test. The unsigned MSIX is never modified.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root 'dist\windows-store'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $dist 'smoke' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$source = Get-ChildItem -LiteralPath $dist -Filter 'KlipaPlayer-*-x64.msix' -File | Select-Object -First 1
if (-not $source) { throw 'The Store MSIX is missing. Run tool/package_msix.ps1 first.' }
$manifest = [xml](Get-Content -LiteralPath (Join-Path $dist 'AppxManifest.xml') -Raw)
$identityName = $manifest.Package.Identity.Name
$publisher = $manifest.Package.Identity.Publisher
$appId = $manifest.Package.Applications.Application.Id

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'The MSIX smoke test trusts a test certificate machine-wide and needs an elevated shell.' }
if (Get-AppxPackage -Name $identityName) {
  throw "A package named $identityName is already installed; refusing to replace it."
}

$kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
$signTool = Get-ChildItem -LiteralPath $kits -Filter signtool.exe -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.DirectoryName -like '*\x64' } |
  Sort-Object FullName -Descending |
  Select-Object -First 1
if (-not $signTool) { throw 'Windows SDK SignTool was not found.' }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IApplicationActivationManager {
  [PreserveSig]
  int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
    [MarshalAs(UnmanagedType.LPWStr)] string arguments, int options, out uint processId);
}

[ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
class ApplicationActivationManager { }

public static class KlipaPackageActivation {
  public static uint Activate(string appUserModelId) {
    var manager = (IApplicationActivationManager)new ApplicationActivationManager();
    uint processId;
    Marshal.ThrowExceptionForHR(manager.ActivateApplication(appUserModelId, null, 0, out processId));
    return processId;
  }
}
'@

function Save-ScreenPng([string]$Path) {
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = [Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.Size)
  $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
  $graphics.Dispose(); $bitmap.Dispose()
  return "$($bounds.Width)x$($bounds.Height)"
}

# Drives the running app the way a person would (Add playlist URL, Import,
# pick a channel, full screen) and captures the screen at 1920 x 1080, the
# size the Store listing wants. Only public test streams appear.
function Save-StoreScreenshots($App, [string]$Directory, [string]$Playlist) {
  Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
  if (-not ('KlipaInput' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class KlipaInput {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
  public static void Click(int x, int y) {
    SetCursorPos(x, y);
    mouse_event(0x02, 0, 0, 0, UIntPtr.Zero);
    mouse_event(0x04, 0, 0, 0, UIntPtr.Zero);
  }
}
'@
  }
  try { Set-DisplayResolution -Width 1920 -Height 1080 -Force -ErrorAction Stop } catch { }

  $App.Refresh()
  $window = $App.MainWindowHandle
  [void][KlipaInput]::ShowWindow($window, 3)
  [void][KlipaInput]::SetForegroundWindow($window)
  Start-Sleep -Seconds 2
  $root = [Windows.Automation.AutomationElement]::FromHandle($window)

  $find = {
    param([string]$Pattern, [int]$Seconds = 20)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
      $all = $root.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
      foreach ($element in $all) {
        if ($element.Current.Name -like $Pattern -and -not $element.Current.BoundingRectangle.IsEmpty) { return $element }
      }
      Start-Sleep -Milliseconds 500
    }
    throw "No UI element named like '$Pattern'."
  }
  $click = {
    param($Element)
    $r = $Element.Current.BoundingRectangle
    [KlipaInput]::Click([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2))
    Start-Sleep -Milliseconds 800
  }

  & $click (& $find 'Add playlist URL')
  & $click (& $find '*Playlist address*')
  [Windows.Forms.SendKeys]::SendWait($Playlist)
  & $click (& $find 'Import')
  & $click (& $find '*Big Buck Bunny*' 45)
  Start-Sleep -Seconds 12
  $size = Save-ScreenPng (Join-Path $Directory 'store-01-library.png')
  [Windows.Forms.SendKeys]::SendWait('f')
  Start-Sleep -Seconds 5
  [void](Save-ScreenPng (Join-Path $Directory 'store-02-full-screen.png'))
  [Windows.Forms.SendKeys]::SendWait('{ESC}')
  return "captured at $size"
}

$work = Join-Path ([IO.Path]::GetTempPath()) "klipa-msix-smoke-$PID"
New-Item -ItemType Directory -Path $work -Force | Out-Null
$signed = Join-Path $work 'KlipaPlayer-test-signed.msix'
Copy-Item -LiteralPath $source.FullName -Destination $signed

$cert = $null
$trusted = $null
$app = $null
$installed = $false
$results = [ordered]@{ package = $source.Name; identityName = $identityName }
try {
  $cert = New-SelfSignedCertificate -Type Custom -Subject $publisher `
    -KeyUsage DigitalSignature -FriendlyName 'Klipa MSIX smoke test (throwaway)' `
    -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddDays(1) `
    -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
  $cer = Join-Path $work 'smoke.cer'
  Export-Certificate -Cert $cert -FilePath $cer | Out-Null
  $trusted = Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople'

  & $signTool.FullName sign /fd SHA256 /sha1 $cert.Thumbprint $signed
  if ($LASTEXITCODE -ne 0) { throw 'Test signing of the MSIX copy failed.' }

  Add-AppxPackage -Path $signed
  $installed = $true
  $package = Get-AppxPackage -Name $identityName
  if (-not $package) { throw 'The package did not register.' }
  $results.packageFullName = $package.PackageFullName
  $results.installLocation = $package.InstallLocation

  $aumid = "$($package.PackageFamilyName)!$appId"
  $processId = [KlipaPackageActivation]::Activate($aumid)
  $app = Get-Process -Id $processId
  Start-Sleep -Seconds 8
  $app.Refresh()
  if ($app.HasExited) { throw "Klipa Player exited during startup with code $($app.ExitCode)." }
  if (-not $app.Path.StartsWith($package.InstallLocation, [StringComparison]::OrdinalIgnoreCase)) {
    throw "The activated process does not run from the package: $($app.Path)"
  }
  $results.processPath = $app.Path
  $results.responding = $app.Responding
  $results.mainWindowTitle = $app.MainWindowTitle
  # Windows keeps a packaged app's redirected data here and deletes it on removal.
  $packageData = Join-Path $env:LOCALAPPDATA "Packages\$($package.PackageFamilyName)"
  $results.packageDataFiles = @(Get-ChildItem -LiteralPath $packageData -Recurse -File -ErrorAction SilentlyContinue).Count

  $connections = @(Get-NetTCPConnection -OwningProcess $app.Id -ErrorAction SilentlyContinue)
  $results.tcpConnections = $connections.Count
  if ($connections.Count -ne 0) {
    throw "Clean startup opened $($connections.Count) TCP connection(s)."
  }
  $modules = @($app.Modules | ForEach-Object { $_.FileName })
  $packagedMpv = Join-Path $package.InstallLocation 'libmpv-2.dll'
  $results.libmpvLoadedAtStart = [bool]($modules | Where-Object {
    [string]::Equals($_, $packagedMpv, [StringComparison]::OrdinalIgnoreCase)
  })

  try {
    [void](Save-ScreenPng (Join-Path $OutputDirectory 'msix-first-start.png'))
  } catch {
    $results.screenshot = "not captured: $($_.Exception.Message)"
  }

  if ($CaptureScreenshots) {
    try {
      $results.screenshots = Save-StoreScreenshots -App $app -Directory $OutputDirectory -Playlist $ScreenshotPlaylist
    } catch {
      $results.screenshots = "not captured: $($_.Exception.Message)"
    }
  }

  Stop-Process -Id $app.Id -Force
  $app.WaitForExit(10000) | Out-Null
  Remove-AppxPackage -Package $package.PackageFullName
  $installed = $false
  if (Get-AppxPackage -Name $identityName) { throw 'The package is still registered after removal.' }
  $results.packageDataRemoved = -not (Test-Path -LiteralPath $packageData)
  $results.result = 'passed'

  if ($RunAppCert) {
    $appCert = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\App Certification Kit\appcert.exe'
    if (Test-Path -LiteralPath $appCert) {
      $report = Join-Path $OutputDirectory 'appcert-report.xml'
      & $appCert reset | Out-Null
      $run = Start-Process -FilePath $appCert -PassThru -NoNewWindow -ArgumentList @(
        'test', '-appxpackagepath', "`"$signed`"", '-reportoutputpath', "`"$report`""
      )
      if (-not $run.WaitForExit(1500000)) {
        Stop-Process -Id $run.Id -Force -ErrorAction SilentlyContinue
        $results.appCert = 'timed out after 25 minutes'
      } elseif (Test-Path -LiteralPath $report) {
        $overall = ([xml](Get-Content -LiteralPath $report -Raw)).REPORT.OVERALL_RESULT
        $results.appCert = "exit $($run.ExitCode), overall $overall"
      } else {
        $results.appCert = "exit $($run.ExitCode), no report"
      }
      Get-AppxPackage -Name $identityName | Remove-AppxPackage
    } else {
      $results.appCert = 'App Certification Kit not installed on this machine'
    }
  }
} catch {
  $results.result = "failed: $($_.Exception.Message)"
  throw
} finally {
  if ($null -ne $app -and -not $app.HasExited) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue }
  if ($installed) { Get-AppxPackage -Name $identityName | Remove-AppxPackage -ErrorAction SilentlyContinue }
  if ($trusted) { Remove-Item -LiteralPath "Cert:\LocalMachine\TrustedPeople\$($trusted.Thumbprint)" -ErrorAction SilentlyContinue }
  if ($cert) { Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($cert.Thumbprint)" -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  $results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'msix-smoke.json') -Encoding utf8
  $results | Format-List | Out-String | Write-Host
}
Write-Host 'Windows Store MSIX test-signed install, packaged start, zero-network, and removal smoke passed.'
