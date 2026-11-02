param(
  [Parameter(Mandatory = $true)]
  [string]$Repository,
  [string]$Tag = 'media-runtime-v1'
)

# Downloads Klipa's vetted Windows media runtime from its GitHub release and
# stages it in dist\windows-media\current, where tool/build_windows.ps1
# expects it. The archive and the DLL must match the hashes pinned in
# third_party/windows-media/<tag>.sha256, so a replaced release asset is
# refused instead of shipped.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent $PSScriptRoot

if ($Repository -notmatch '^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$') { throw 'Repository must be owner/name.' }
if ($Tag -notmatch '^media-runtime-v\d+$') { throw 'Tag must be media-runtime-v<number>.' }

$pins = Join-Path $root "third_party\windows-media\$Tag.sha256"
if (-not (Test-Path -LiteralPath $pins)) { throw "No pinned hashes for ${Tag}: $pins" }
$expected = @{}
foreach ($line in Get-Content -LiteralPath $pins) {
  if ($line -match '^([0-9a-f]{64}) \*(\S+)$') { $expected[$Matches[2]] = $Matches[1] }
}
foreach ($name in 'windows-media-runtime.zip', 'libmpv-2.dll') {
  if (-not $expected.ContainsKey($name)) { throw "$pins does not pin $name." }
}

$mediaDir = Join-Path $root 'dist\windows-media'
$mediaRoot = Join-Path $mediaDir 'current'
if (Test-Path -LiteralPath $mediaRoot) { Remove-Item -LiteralPath $mediaRoot -Recurse -Force }
New-Item -ItemType Directory -Path $mediaRoot -Force | Out-Null

$zip = Join-Path $mediaDir 'windows-media-runtime.zip'
Invoke-WebRequest -Uri "https://github.com/$Repository/releases/download/$Tag/windows-media-runtime.zip" -OutFile $zip
$zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($zipHash -ne $expected['windows-media-runtime.zip']) {
  throw "windows-media-runtime.zip from $Tag does not match its pinned SHA-256."
}

Expand-Archive -LiteralPath $zip -DestinationPath $mediaRoot -Force
$dll = Join-Path $mediaRoot 'libmpv-2.dll'
$dllHash = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant()
if ($dllHash -ne $expected['libmpv-2.dll']) { throw 'The staged libmpv-2.dll does not match its pinned SHA-256.' }

Write-Host "Vetted Windows media runtime $Tag staged: libmpv-2.dll $dllHash"
