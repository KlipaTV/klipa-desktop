param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mirror = Join-Path $env:USERPROFILE 'develop\klipa-player-windows-native'
$bundle = Join-Path $mirror 'build\windows\x64\runner\Release'
$dist = Join-Path $root 'dist\windows'

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
& $iscc "/DBundleDir=$bundle" "/DOutputDir=$dist" "/DAppVersion=$version" $script
if ($LASTEXITCODE -ne 0) { throw 'Windows installer creation failed.' }

Write-Host "Windows installer: $(Join-Path $dist 'KlipaPlayer-Setup-x64.exe')"
Write-Host "Portable archive: $portable"
