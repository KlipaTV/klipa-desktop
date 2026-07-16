param(
  [Parameter(Mandatory = $true)]
  [string]$Bundle,
  [Parameter(Mandatory = $true)]
  [string]$Output
)

$ErrorActionPreference = 'Stop'

function Get-Sha256([string]$Path) {
  $stream = [IO.File]::OpenRead($Path)
  $algorithm = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
  } finally {
    $algorithm.Dispose()
    $stream.Dispose()
  }
}

$bundlePath = [IO.Path]::GetFullPath($Bundle)
if (-not (Test-Path -LiteralPath $bundlePath -PathType Container)) {
  throw "Windows release bundle is missing: $bundlePath"
}
$bundlePrefix = $bundlePath.TrimEnd(
  [IO.Path]::DirectorySeparatorChar,
  [IO.Path]::AltDirectorySeparatorChar
) + [IO.Path]::DirectorySeparatorChar

$items = Get-ChildItem -LiteralPath $bundlePath -Recurse -File |
  Sort-Object FullName |
  ForEach-Object {
    if (-not $_.FullName.StartsWith($bundlePrefix, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Inventory file escaped the release bundle: $($_.FullName)"
    }
    $relative = $_.FullName.Substring($bundlePrefix.Length)
    $version = $_.VersionInfo
    [ordered]@{
      path = $relative.Replace([IO.Path]::DirectorySeparatorChar, '/')
      bytes = $_.Length
      sha256 = Get-Sha256 $_.FullName
      fileVersion = $version.FileVersion
      productName = $version.ProductName
      companyName = $version.CompanyName
    }
  }

$document = [ordered]@{
  schema = 1
  platform = 'windows-x64'
  files = @($items)
}
$outputPath = [IO.Path]::GetFullPath($Output)
$outputParent = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
$document | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $outputPath -Encoding utf8
Write-Host "Windows native inventory: $outputPath"
