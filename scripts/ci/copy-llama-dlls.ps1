# Copy llama.cpp DLLs to build and lib directories
# Usage: copy-llama-dlls.ps1 -Arch x64|arm64 -SourceDir <dir> -BuildDir <dir>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("x64", "arm64")]
    [string]$Arch,

    [Parameter(Mandatory=$false)]
    [string]$SourceDir = "llama.cpp-build",

    [Parameter(Mandatory=$false)]
    [string]$BuildDir = "build"
)

$ErrorActionPreference = "Stop"

# Set directories based on architecture
if ($Arch -eq "x64") {
    $outDir = Join-Path $BuildDir "x64\release"
    $libDir = "src\AzooKeyKanaKanjiConverter\lib\windows"
} else {
    $outDir = Join-Path $BuildDir "arm64\release"
    $libDir = "src\AzooKeyKanaKanjiConverter\lib\windows-arm64"
}

# Create directories
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
New-Item -ItemType Directory -Force -Path $libDir | Out-Null

# DLLs to copy
$dlls = @("ggml.dll", "ggml-base.dll", "ggml-cpu.dll", "ggml-vulkan.dll", "llama.dll")

Write-Host "Copying llama.cpp DLLs for $Arch..."

foreach ($dll in $dlls) {
    $src = Join-Path $SourceDir $dll
    if (Test-Path $src) {
        Copy-Item $src -Destination $outDir -Force
        Copy-Item $src -Destination $libDir -Force
        Write-Host "  Copied: $dll"
    } else {
        Write-Host "  Warning: $dll not found at $src"
    }
}

# Copy .lib files for linking
Get-ChildItem -Path $SourceDir -Filter "*.lib" -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item $_.FullName -Destination $libDir -Force
    Write-Host "  Copied lib: $($_.Name)"
}

Write-Host "Done."
