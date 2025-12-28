# Download Qt source for Mozc build
# Usage: download-qt.ps1 -Version <version> -OutputDir <dir>

param(
    [Parameter(Mandatory=$false)]
    [string]$Version = "6.9.1",

    [Parameter(Mandatory=$false)]
    [string]$OutputDir = "mozc/src/third_party_cache"
)

$ErrorActionPreference = "Stop"

$fileName = "qtbase-everywhere-src-$Version.tar.xz"
$outputPath = Join-Path $OutputDir $fileName

# Check if already exists
if (Test-Path $outputPath) {
    Write-Host "Qt source already exists: $outputPath"
    exit 0
}

# Create output directory
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# Build URL
$majorMinor = $Version -replace '\.\d+$', ''
$url = "https://download.qt.io/official_releases/qt/$majorMinor/$Version/submodules/$fileName"

Write-Host "Downloading Qt $Version from:"
Write-Host "  $url"
Write-Host "To: $outputPath"

try {
    Invoke-WebRequest -Uri $url -OutFile $outputPath -UseBasicParsing
    Write-Host "Download completed."
} catch {
    Write-Host "Error downloading Qt: $_"
    exit 1
}
