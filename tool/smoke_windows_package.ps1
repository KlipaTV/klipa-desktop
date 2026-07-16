$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'dist\windows\KlipaPlayer-Setup-x64.exe'
if (-not (Test-Path -LiteralPath $source)) { throw 'Windows installer is missing.' }

$localSetup = Join-Path $env:TEMP 'KlipaPlayer-Setup-x64.exe'
$target = Join-Path $env:TEMP 'KlipaPlayerInstallSmoke'
Copy-Item -LiteralPath $source -Destination $localSetup -Force
$app = $null
if (Test-Path -LiteralPath $target) {
  $resolved = [IO.Path]::GetFullPath($target)
  $tempRoot = [IO.Path]::GetFullPath($env:TEMP)
  if (-not $resolved.StartsWith($tempRoot)) { throw 'Unsafe smoke target.' }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}

try {
  $installer = Start-Process -FilePath $localSetup -ArgumentList @(
    '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=$target"
  ) -WindowStyle Hidden -Wait -PassThru
  if ($installer.ExitCode -ne 0) { throw "Installer exit $($installer.ExitCode)." }

  $exe = Join-Path $target 'klipa_player.exe'
  if (-not (Test-Path -LiteralPath $exe)) { throw 'Installed executable is missing.' }
  $app = Start-Process -FilePath $exe -WindowStyle Hidden -PassThru
  Start-Sleep -Seconds 5
  $connections = @(Get-NetTCPConnection -OwningProcess $app.Id -ErrorAction SilentlyContinue)
  if ($connections.Count -ne 0) {
    throw "Clean startup opened $($connections.Count) TCP connection(s)."
  }
  Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 1

  $uninstaller = Join-Path $target 'unins000.exe'
  $uninstall = Start-Process -FilePath $uninstaller -ArgumentList @(
    '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
  ) -WindowStyle Hidden -Wait -PassThru
  if ($uninstall.ExitCode -ne 0) { throw "Uninstaller exit $($uninstall.ExitCode)." }
  Write-Host 'Windows install, clean startup, zero-network, and uninstall smoke passed.'
} finally {
  if ($null -ne $app -and -not $app.HasExited) {
    Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath $localSetup -Force -ErrorAction SilentlyContinue
}
