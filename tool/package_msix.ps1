param(
  [switch]$SkipBuild,
  [string]$IdentityName,
  [string]$Publisher,
  [string]$PublisherDisplayName,
  [string]$DisplayName,
  # CI validation only: a package with a placeholder identity cannot be
  # submitted to the Store, so it is never the default.
  [switch]$AllowPlaceholderIdentity
)

# Packages the Windows release bundle as an unsigned MSIX for Microsoft Store
# submission. The Store signs packages after certification; nothing here
# signs or publishes anything.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mirror = Join-Path $env:USERPROFILE 'develop\klipa-player-windows-native'
$bundle = Join-Path $mirror 'build\windows\x64\runner\Release'
$msixSource = Join-Path $root 'packaging\windows\msix'
$dist = Join-Path $root 'dist\windows-store'

function Find-VcRedistCrtDirectory {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  if (-not (Test-Path -LiteralPath $vswhere)) { return $null }
  $vsRoot = & $vswhere -latest -products * -property installationPath 2>$null |
    Select-Object -First 1
  if (-not $vsRoot) { return $null }
  $redist = Join-Path $vsRoot 'VC\Redist\MSVC'
  if (-not (Test-Path -LiteralPath $redist)) { return $null }
  $crt = Get-ChildItem -LiteralPath $redist -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    ForEach-Object {
      Get-ChildItem -Path (Join-Path $_.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue
    } |
    Select-Object -First 1
  if ($null -eq $crt) { return $null }
  return $crt.FullName
}

function Find-SdkTool([string]$Name) {
  $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
  $candidate = Get-ChildItem -LiteralPath $kits -Filter $Name -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -like '*\x64' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
  if ($null -eq $candidate) { throw "Windows SDK $Name was not found." }
  return $candidate.FullName
}

function Reset-Directory([string]$Path) {
  $resolved = [IO.Path]::GetFullPath($Path)
  if (-not $resolved.StartsWith([IO.Path]::GetFullPath($dist) + [IO.Path]::DirectorySeparatorChar)) {
    throw "Refusing to reset a directory outside $dist"
  }
  if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
  New-Item -ItemType Directory -Path $resolved -Force | Out-Null
}

$identity = Get-Content -LiteralPath (Join-Path $msixSource 'store-identity.json') -Raw | ConvertFrom-Json
if ($IdentityName) { $identity.identityName = $IdentityName }
if ($Publisher) { $identity.publisher = $Publisher }
if ($PublisherDisplayName) { $identity.publisherDisplayName = $PublisherDisplayName }
if ($DisplayName) { $identity.displayName = $DisplayName }

if ($identity.identityName -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{2,49}$') {
  throw 'The Store identity name must be 3 to 50 letters, digits, periods or dashes.'
}
if ($identity.publisher -notmatch '^CN=') {
  throw 'The Store publisher must be the CN=... value from Partner Center.'
}
if (-not $identity.publisherDisplayName -or -not $identity.displayName) {
  throw 'The Store publisher display name and display name are required.'
}
$placeholder = @(
  $identity.identityName, $identity.publisher, $identity.publisherDisplayName, $identity.displayName
) -match 'PLACEHOLDER'
$placeholder = $placeholder.Count -gt 0
if ($placeholder -and -not $AllowPlaceholderIdentity) {
  throw 'store-identity.json still holds placeholders. Copy the values from Partner Center > Product identity, or pass -AllowPlaceholderIdentity for a validation build.'
}

# The Store requires a four-part version whose last part is zero.
$pubspecVersion = (Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(\d+)\.(\d+)\.(\d+)').Matches
if (-not $pubspecVersion) { throw 'pubspec.yaml has no major.minor.patch version.' }
$groups = $pubspecVersion[0].Groups
$version = '{0}.{1}.{2}.0' -f $groups[1].Value, $groups[2].Value, $groups[3].Value

if (-not $SkipBuild) {
  & (Join-Path $PSScriptRoot 'build_windows.ps1') -Configuration release
  if ($LASTEXITCODE -ne 0) { throw 'Windows release validation failed.' }
}
if (-not (Test-Path -LiteralPath (Join-Path $bundle 'klipa_player.exe'))) {
  throw "Windows release bundle is missing: $bundle"
}

# Only a bundle carrying Klipa's vetted media runtime may become a Store package.
$mediaHashFile = Join-Path $bundle 'licenses\windows-media\libmpv-2.dll.sha256'
if (-not (Test-Path -LiteralPath $mediaHashFile)) {
  throw 'The release bundle lacks the vetted media runtime evidence. Build it with tool/build_windows.ps1 -Configuration release.'
}
$expectedMedia = ((Get-Content -LiteralPath $mediaHashFile -Raw).Trim() -split '\s+')[0]
$actualMedia = (Get-FileHash -LiteralPath (Join-Path $bundle 'libmpv-2.dll') -Algorithm SHA256).Hash
if ($actualMedia -ne $expectedMedia) { throw 'The bundled libmpv-2.dll is not the vetted media runtime.' }

New-Item -ItemType Directory -Path $dist -Force | Out-Null
$package = Join-Path $dist 'package'
Reset-Directory $package
Copy-Item -Path (Join-Path $bundle '*') -Destination $package -Recurse

# Same app-local C++ runtime as the installer and portable archive.
$vcRedistCrt = Find-VcRedistCrtDirectory
foreach ($runtime in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  $target = Join-Path $package $runtime
  if (Test-Path -LiteralPath $target) { continue }
  if ($vcRedistCrt -and (Test-Path -LiteralPath (Join-Path $vcRedistCrt $runtime))) {
    Copy-Item -LiteralPath (Join-Path $vcRedistCrt $runtime) -Destination $target
  } else {
    Write-Warning "VC++ redistributable directory not found; copying $runtime from System32."
    Copy-Item -LiteralPath (Join-Path $env:WINDIR "System32\$runtime") -Destination $target
  }
}
foreach ($doc in 'LICENSE', 'NOTICE', 'THIRD_PARTY_NOTICES.md') {
  $docPath = Join-Path $root $doc
  if (-not (Test-Path -LiteralPath $docPath)) { throw "Missing license document: $doc" }
  Copy-Item -LiteralPath $docPath -Destination $package -Force
}
Copy-Item -LiteralPath (Join-Path $msixSource 'Assets') -Destination $package -Recurse

$manifest = Get-Content -LiteralPath (Join-Path $msixSource 'AppxManifest.xml.in') -Raw
$tokens = [ordered]@{
  '@IDENTITY_NAME@' = $identity.identityName
  '@PUBLISHER_DISPLAY_NAME@' = $identity.publisherDisplayName
  '@PUBLISHER@' = $identity.publisher
  '@DISPLAY_NAME@' = $identity.displayName
  '@VERSION@' = $version
}
foreach ($token in $tokens.Keys) {
  $manifest = $manifest.Replace($token, [Security.SecurityElement]::Escape([string]$tokens[$token]))
}
if ($manifest -match '@[A-Z_]+@') { throw 'The MSIX manifest still has an unfilled token.' }
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $package 'AppxManifest.xml'), $manifest, $utf8)

# Index only the manifest and the visual assets, so the scale and target-size
# variants resolve; the Flutter bundle needs no resource index.
$makePri = Find-SdkTool 'makepri.exe'
$makeAppx = Find-SdkTool 'makeappx.exe'
$priRoot = Join-Path $dist 'pri'
Reset-Directory $priRoot
Copy-Item -LiteralPath (Join-Path $package 'AppxManifest.xml') -Destination $priRoot
Copy-Item -LiteralPath (Join-Path $msixSource 'Assets') -Destination $priRoot -Recurse
$priConfig = Join-Path $dist 'priconfig.xml'
& $makePri createconfig /cf $priConfig /dq en-US /pv 10.0.0 /o
if ($LASTEXITCODE -ne 0) { throw 'makepri createconfig failed.' }
# One package, one resources.pri: drop the resource-pack split meant for bundles.
$config = [xml](Get-Content -LiteralPath $priConfig -Raw)
foreach ($packaging in @($config.resources.packaging)) {
  if ($packaging) { [void]$config.resources.RemoveChild($packaging) }
}
$config.Save($priConfig)
& $makePri new /pr $priRoot /cf $priConfig /mn (Join-Path $priRoot 'AppxManifest.xml') `
  /of (Join-Path $package 'resources.pri') /o
if ($LASTEXITCODE -ne 0) { throw 'makepri new failed.' }

Get-ChildItem -LiteralPath $dist -Filter '*.msix' -File | Remove-Item -Force
$msix = Join-Path $dist "KlipaPlayer-$version-x64.msix"
& $makeAppx pack /d $package /p $msix /h SHA256 /o
if ($LASTEXITCODE -ne 0) { throw 'makeappx pack failed.' }

Copy-Item -LiteralPath (Join-Path $package 'AppxManifest.xml') -Destination $dist -Force
[ordered]@{
  version = $version
  identityName = $identity.identityName
  publisher = $identity.publisher
  publisherDisplayName = $identity.publisherDisplayName
  displayName = $identity.displayName
  placeholderIdentity = $placeholder
  libmpvSha256 = $actualMedia.ToLowerInvariant()
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dist 'identity.json') -Encoding utf8

$hash = (Get-FileHash -LiteralPath $msix -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash *$(Split-Path -Leaf $msix)" | Set-Content -LiteralPath (Join-Path $dist 'SHA256SUMS.txt') -Encoding ascii

if ($placeholder) {
  Write-Warning 'Built with a placeholder Store identity: this package is for validation and cannot be submitted.'
}
Write-Host "Store package: $msix"
