# Copy Swift Runtime DLLs to build directory
# Usage: copy-swift-runtime.ps1 -OutputDir <dir>

[CmdletBinding(DefaultParameterSetName="Copy")]
param(
    [Parameter(Mandatory=$true, ParameterSetName="Copy", Position=0)]
    [string]$OutputDir,

    [Parameter(Mandatory=$true, ParameterSetName="List")]
    [switch]$ListOnly
)

$ErrorActionPreference = "Continue"

# DLLs to copy
$dlls = @(
    "swiftCore.dll",
    "swiftCRT.dll",
    "swiftDispatch.dll",
    "swift_Concurrency.dll",
    "swift_StringProcessing.dll",
    "swift_RegexParser.dll",
    "swiftRegexBuilder.dll",
    "swiftWinSDK.dll",
    "Foundation.dll",
    "FoundationEssentials.dll",
    "FoundationNetworking.dll",
    "FoundationInternationalization.dll",
    "_FoundationICU.dll",
    "BlocksRuntime.dll",
    "dispatch.dll"
)

if ($ListOnly) {
    $dlls | ForEach-Object { Write-Output $_ }
    exit 0
}

# Search paths for Swift Runtime
$runtimeDirs = @(
    "$env:LOCALAPPDATA\Programs\Swift\Runtimes",
    "$env:ProgramFiles\Swift\Runtimes",
    "C:\Library\Swift\Runtimes"
)

$foundRuntime = $null
$searched = @()

foreach ($dir in $runtimeDirs) {
    $searched += $dir
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

# Fallback 1: swiftCore.dll next to swift.exe on PATH
# (setup-swift がツールキャッシュから復元した場合、インストーラ形式の
#  %LOCALAPPDATA%\Programs\Swift\Runtimes が存在しないことがある)
if (-not $foundRuntime) {
    $swift = Get-Command swift.exe -ErrorAction SilentlyContinue
    if ($swift) {
        $bin = Split-Path $swift.Source
        $searched += $bin
        if (Test-Path (Join-Path $bin "swiftCore.dll")) {
            $foundRuntime = $bin
        }
    }
}

# Fallback 2: derive toolchain root from SDKROOT (hostedtoolcache layout)
if (-not $foundRuntime -and $env:SDKROOT) {
    $root = $env:SDKROOT -replace '\\Platforms\\.*$', ''
    $runtimesRoot = Join-Path $root "Runtimes"
    $searched += $runtimesRoot
    if (Test-Path $runtimesRoot) {
        $hit = Get-ChildItem -Path $runtimesRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "usr\bin" } |
            Where-Object { Test-Path (Join-Path $_ "swiftCore.dll") } |
            Select-Object -First 1
        if ($hit) { $foundRuntime = $hit }
    }
}

if (-not $foundRuntime) {
    Write-Host "Warning: Swift Runtime not found. Searched:"
    $searched | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

Write-Host "Found Swift Runtime at: $foundRuntime"

# Create output directory
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$copied = 0
$missing = @()
foreach ($dll in $dlls) {
    $src = Join-Path $foundRuntime $dll
    if (Test-Path $src) {
        Copy-Item $src -Destination $OutputDir -Force
        Write-Host "  Copied: $dll"
        $copied++
    } else {
        $missing += $dll
    }
}

if ($missing.Count -gt 0) {
    Write-Error "Missing required Swift runtime DLLs in ${foundRuntime}: $($missing -join ', ')"
    exit 1
}

Write-Host "Copied $copied Swift Runtime DLLs."
