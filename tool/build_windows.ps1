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
  /XD .git .build .dart_tool .idea build dist ephemeral failures `
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
  if ($Configuration -eq 'release') {
    $mediaRoot = Join-Path $source 'dist\windows-media\current'
    $mediaRuntime = Join-Path $mediaRoot 'libmpv-2.dll'
    $mediaHashFile = Join-Path $mediaRoot 'libmpv-2.dll.sha256'
    if (-not (Test-Path -LiteralPath $mediaRuntime) -or
        -not (Test-Path -LiteralPath $mediaHashFile)) {
      throw 'The vetted Windows media runtime is missing. Run tool/build_windows_media.sh first.'
    }
    $expectedHash = ((Get-Content -LiteralPath $mediaHashFile -Raw).Trim() -split '\s+')[0]
    $actualHash = (Get-FileHash -LiteralPath $mediaRuntime -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
      throw 'The vetted Windows media runtime failed its SHA-256 check.'
    }

    Copy-Item -LiteralPath $mediaRuntime -Destination (Join-Path $bundle 'libmpv-2.dll') -Force
    $notices = Join-Path $bundle 'licenses\windows-media'
    if (Test-Path -LiteralPath $notices) { Remove-Item -LiteralPath $notices -Recurse -Force }
    New-Item -ItemType Directory -Path $notices -Force | Out-Null
    Copy-Item -Path (Join-Path $mediaRoot 'licenses\*') -Destination $notices -Force
    foreach ($provenance in @(
      'compiled-targets.txt',
      'libmpv-2.dll.sha256',
      'mpv-winbuild-commit.txt',
      'mpv-winbuild-lgpl.patch',
      'mpv-winbuild-lgpl.patch.sha256',
      'source-revisions.tsv',
      'toolchain-versions.txt'
    )) {
      Copy-Item -LiteralPath (Join-Path $mediaRoot $provenance) -Destination $notices -Force
    }
    Copy-Item -LiteralPath (Join-Path $source 'NOTICE') -Destination (Join-Path $bundle 'NOTICE.txt') -Force
    Copy-Item -LiteralPath (Join-Path $source 'THIRD_PARTY_NOTICES.md') `
      -Destination (Join-Path $bundle 'THIRD_PARTY_NOTICES.md') -Force
  }

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
