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
$versionFile = "scripts\llama-cpp-version.env"
$llamaCppVersion = (Get-Content $versionFile | Where-Object { $_ -match "^LLAMA_CPP_VERSION=" } | Select-Object -First 1) -replace "^LLAMA_CPP_VERSION=", ""
$buildMarker = "$llamaCppVersion-dl-vulkan"

# Create directories
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
New-Item -ItemType Directory -Force -Path $libDir | Out-Null

# DLLs to copy (Vulkan is packaged as a dynamically loaded module; not loaded by default)
$dlls = @("ggml.dll", "ggml-base.dll", "ggml-cpu.dll", "ggml-vulkan.dll", "llama.dll")
$libs = @("llama.lib", "ggml.lib", "ggml-base.lib")

Write-Host "Copying llama.cpp DLLs for $Arch..."

$missingDlls = @()
foreach ($dll in $dlls) {
    $src = Join-Path $SourceDir $dll
    if (Test-Path $src) {
        Copy-Item $src -Destination $outDir -Force
        Copy-Item $src -Destination $libDir -Force
        Write-Host "  Copied: $dll"
    } else {
        $missingDlls += $src
    }
}

if ($missingDlls.Count -gt 0) {
    throw "Missing llama.cpp DLLs: $($missingDlls -join ', ')"
}

# Copy .lib files for linking. ggml-cpu.lib is not generated with GGML_BACKEND_DL=ON.
Remove-Item -Path (Join-Path $libDir "ggml-cpu.lib") -ErrorAction SilentlyContinue
$missingLibs = @()
foreach ($lib in $libs) {
    $src = Join-Path $SourceDir $lib
    if (Test-Path $src) {
        Copy-Item $src -Destination $libDir -Force
        Write-Host "  Copied lib: $lib"
    } else {
        $missingLibs += $src
    }
}

if ($missingLibs.Count -gt 0) {
    throw "Missing llama.cpp import libs: $($missingLibs -join ', ')"
}

Set-Content -Path (Join-Path $libDir ".myime-llama-build") -Value $buildMarker -NoNewline
Write-Host "  Wrote build marker: $buildMarker"

Write-Host "Done."
