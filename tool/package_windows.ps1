param(
  [switch]$SkipBuild,
  [string]$SigningThumbprint,
  [string]$TimestampUrl
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mirror = Join-Path $env:USERPROFILE 'develop\klipa-player-windows-native'
$bundle = Join-Path $mirror 'build\windows\x64\runner\Release'
$dist = Join-Path $root 'dist\windows'

function Find-SignTool {
  $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
  $candidate = Get-ChildItem -LiteralPath $kits -Filter signtool.exe -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -like '*\x64' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
  if ($null -eq $candidate) { throw 'Windows SDK SignTool was not found.' }
  return $candidate.FullName
}

$signTool = $null
$normalizedThumbprint = $SigningThumbprint.Replace(' ', '')
if ($normalizedThumbprint) {
  if ($normalizedThumbprint -notmatch '^[0-9A-Fa-f]{40}$') {
    throw 'SigningThumbprint must be a 40-character certificate thumbprint.'
  }
  $timestamp = $null
  if (-not [Uri]::TryCreate($TimestampUrl, [UriKind]::Absolute, [ref]$timestamp) -or
      $timestamp.Scheme -ne 'https') {
    throw 'TimestampUrl must be an explicit HTTPS RFC 3161 endpoint.'
  }
  if (-not (Test-Path -LiteralPath "Cert:\CurrentUser\My\$normalizedThumbprint")) {
    throw 'The signing certificate is not in the current user certificate store.'
  }
  $signTool = Find-SignTool
} elseif ($TimestampUrl) {
  throw 'TimestampUrl requires SigningThumbprint.'
}

if (-not $SkipBuild) {
  & (Join-Path $PSScriptRoot 'build_windows.ps1') -Configuration release
  if ($LASTEXITCODE -ne 0) { throw 'Windows release validation failed.' }
}
if (-not (Test-Path -LiteralPath (Join-Path $bundle 'klipa_player.exe'))) {
  throw "Windows release bundle is missing: $bundle"
}

New-Item -ItemType Directory -Path $dist -Force | Out-Null
foreach ($runtime in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  $target = Join-Path $bundle $runtime
  if (-not (Test-Path -LiteralPath $target)) {
    Copy-Item -LiteralPath (Join-Path $env:WINDIR "System32\$runtime") -Destination $target
  }
}

if ($signTool) {
  & $signTool sign /sha1 $normalizedThumbprint /fd SHA256 /td SHA256 `
    /tr $TimestampUrl /d 'Klipa Player' (Join-Path $bundle 'klipa_player.exe')
  if ($LASTEXITCODE -ne 0) { throw 'Windows executable signing failed.' }
  & $signTool verify /pa (Join-Path $bundle 'klipa_player.exe')
  if ($LASTEXITCODE -ne 0) { throw 'Windows executable signature verification failed.' }
}

$portable = Join-Path $dist 'KlipaPlayer-Portable-x64.zip'
if (Test-Path -LiteralPath $portable) { Remove-Item -LiteralPath $portable }
Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $portable -CompressionLevel Optimal

$iscc = @(
  (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
  (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
  (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 is required to build the Windows installer.' }

$version = ((Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*([^+]+)').Matches.Groups[1].Value)
$script = Join-Path $root 'packaging\windows\klipa-player.iss'
$compilerArguments = @(
  "/DBundleDir=$bundle",
  "/DOutputDir=$dist",
  "/DAppVersion=$version"
)
if ($signTool) {
  $signCommand = '"{0}" sign /sha1 {1} /fd SHA256 /td SHA256 /tr "{2}" /d "Klipa Player" $f' -f `
    $signTool, $normalizedThumbprint, $TimestampUrl
  $compilerArguments += "/Sklipa=$signCommand"
  $compilerArguments += '/DSigning=1'
}
& $iscc @compilerArguments $script
if ($LASTEXITCODE -ne 0) { throw 'Windows installer creation failed.' }

if ($signTool) {
  $setup = Join-Path $dist 'KlipaPlayer-Setup-x64.exe'
  & $signTool verify /pa $setup
  if ($LASTEXITCODE -ne 0) { throw 'Windows installer signature verification failed.' }
}

Write-Host "Windows installer: $(Join-Path $dist 'KlipaPlayer-Setup-x64.exe')"
Write-Host "Portable archive: $portable"
