param(
  [ValidateSet('debug', 'profile', 'release')]
  [string]$Configuration = 'debug'
)

$ErrorActionPreference = 'Stop'

$source = Split-Path -Parent $PSScriptRoot
$developRoot = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'develop'))
$mirror = [IO.Path]::GetFullPath(
  (Join-Path $developRoot 'klipa-player-windows-native')
)
$flutter = Join-Path $env:USERPROFILE 'develop\flutter\bin\flutter.bat'

if (-not $mirror.StartsWith($developRoot + [IO.Path]::DirectorySeparatorChar)) {
  throw "Refusing to synchronize outside $developRoot"
}
if (-not (Test-Path -LiteralPath $flutter)) {
  throw "Windows Flutter was not found at $flutter"
}

New-Item -ItemType Directory -Path $mirror -Force | Out-Null

& robocopy $source $mirror /MIR /R:2 /W:1 /NJH /NJS /NFL /NDL /NP `
  /XD .git .dart_tool .idea build ephemeral `
  /XF .flutter-plugins-dependencies '*.iml'
$copyExitCode = $LASTEXITCODE
if ($copyExitCode -gt 7) {
  throw "Native mirror synchronization failed with robocopy code $copyExitCode"
}

Push-Location $mirror
try {
  & $flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

  & $flutter analyze --fatal-infos --fatal-warnings
  if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed' }

  & $flutter build windows "--$Configuration"
  if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }

  $bundle = Join-Path $mirror "build\windows\x64\runner\$Configuration"
  $previousPath = $env:PATH
  try {
    $env:PATH = "$bundle;$previousPath"
    & $flutter test
    if ($LASTEXITCODE -ne 0) { throw 'flutter test failed' }
  } finally {
    $env:PATH = $previousPath
  }
} finally {
  Pop-Location
}

Write-Host "Native bundle: $mirror\build\windows\x64\runner\$Configuration"
