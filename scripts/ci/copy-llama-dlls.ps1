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
} else {
    $outDir = Join-Path $BuildDir "arm64\release"
}
# Always use lib/windows for .lib files (Swift Package.swift references this path)
$libDir = "src\AzooKeyKanaKanjiConverter\lib\windows"

# Create directories
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
New-Item -ItemType Directory -Force -Path $libDir | Out-Null

# DLLs to copy (CPU backend only — Vulkan disabled, see build-llama-cpp.bat)
$dlls = @("ggml.dll", "ggml-base.dll", "ggml-cpu.dll", "llama.dll")

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
