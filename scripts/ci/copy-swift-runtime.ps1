# Copy Swift Runtime DLLs to build directory
# Usage: copy-swift-runtime.ps1 -OutputDir <dir>

param(
    [Parameter(Mandatory=$true)]
    [string]$OutputDir
)

$ErrorActionPreference = "Continue"

# Search paths for Swift Runtime
$runtimeDirs = @(
    "$env:LOCALAPPDATA\Programs\Swift\Runtimes",
    "$env:ProgramFiles\Swift\Runtimes",
    "C:\Library\Swift\Runtimes"
)

$foundRuntime = $null

foreach ($dir in $runtimeDirs) {
    if (Test-Path $dir) {
        $subdirs = Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue
        foreach ($subdir in $subdirs) {
            $candidate = Join-Path $subdir.FullName "usr\bin\swiftCore.dll"
            if (Test-Path $candidate) {
                $foundRuntime = Join-Path $subdir.FullName "usr\bin"
                break
            }
        }
    }
    if ($foundRuntime) { break }
}

if (-not $foundRuntime) {
    Write-Host "Warning: Swift Runtime not found"
    exit 1
}

Write-Host "Found Swift Runtime at: $foundRuntime"

# Create output directory
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# DLLs to copy
$dlls = @(
    "swiftCore.dll",
    "swiftCRT.dll",
    "swiftDispatch.dll",
    "swift_Concurrency.dll",
    "swiftWinSDK.dll",
    "Foundation.dll",
    "FoundationEssentials.dll",
    "FoundationInternationalization.dll",
    "_FoundationICU.dll",
    "BlocksRuntime.dll",
    "dispatch.dll"
)

$copied = 0
foreach ($dll in $dlls) {
    $src = Join-Path $foundRuntime $dll
    if (Test-Path $src) {
        Copy-Item $src -Destination $OutputDir -Force
        Write-Host "  Copied: $dll"
        $copied++
    }
}

Write-Host "Copied $copied Swift Runtime DLLs."
