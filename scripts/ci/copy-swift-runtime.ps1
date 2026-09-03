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

$swift = Get-Command swift.exe -ErrorAction SilentlyContinue
$toolchainVersion = $null

if ($swift -and $swift.Source -match '[\\/]Toolchains[\\/]([^\\/]+)\+Asserts[\\/]usr[\\/]bin[\\/]swift\.exe$') {
    $toolchainVersion = $Matches[1]
} elseif ($swift) {
    $versionOutput = (& $swift.Source --version 2>&1 | Out-String)
    if ($versionOutput -match 'Swift version\s+([0-9]+(?:\.[0-9]+){1,2})') {
        $toolchainVersion = $Matches[1]
    }
}

if (-not $toolchainVersion) {
    Write-Warning "Could not determine the Swift toolchain version; using the first available runtime."
}

$foundRuntime = $null
$foundRuntimeVersion = $null
$searched = @()

# Prefer the runtime whose version matches the active Swift toolchain.
if ($toolchainVersion) {
    foreach ($dir in $runtimeDirs) {
        $candidateDir = Join-Path (Join-Path $dir $toolchainVersion) "usr\bin"
        $searched += $candidateDir
        if (Test-Path (Join-Path $candidateDir "swiftCore.dll")) {
            $foundRuntime = $candidateDir
            $foundRuntimeVersion = $toolchainVersion
            break
        }
    }
}

# If the toolchain version is unknown, preserve the previous search order.
if (-not $foundRuntime -and -not $toolchainVersion) {
    foreach ($dir in $runtimeDirs) {
        $searched += $dir
        if (Test-Path $dir) {
            $subdirs = Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue
            foreach ($subdir in $subdirs) {
                $candidate = Join-Path $subdir.FullName "usr\bin\swiftCore.dll"
                if (Test-Path $candidate) {
                    $foundRuntime = Join-Path $subdir.FullName "usr\bin"
                    $foundRuntimeVersion = $subdir.Name
                    break
                }
            }
        }
        if ($foundRuntime) { break }
    }
}

# Fallback 1: swiftCore.dll next to swift.exe on PATH
# (setup-swift がツールキャッシュから復元した場合、インストーラ形式の
#  %LOCALAPPDATA%\Programs\Swift\Runtimes が存在しないことがある)
if (-not $foundRuntime -and $swift) {
    $bin = Split-Path $swift.Source
    $searched += $bin
    if (Test-Path (Join-Path $bin "swiftCore.dll")) {
        $foundRuntime = $bin
        $foundRuntimeVersion = $toolchainVersion
    }
}

# Fallback 2: derive toolchain root from SDKROOT (hostedtoolcache layout)
if (-not $foundRuntime -and $env:SDKROOT) {
    $root = $env:SDKROOT -replace '\\Platforms\\.*$', ''
    $runtimesRoot = Join-Path $root "Runtimes"
    $searched += $runtimesRoot
    if (Test-Path $runtimesRoot) {
        if ($toolchainVersion) {
            $candidateDir = Join-Path (Join-Path $runtimesRoot $toolchainVersion) "usr\bin"
            $searched += $candidateDir
            if (Test-Path (Join-Path $candidateDir "swiftCore.dll")) {
                $foundRuntime = $candidateDir
                $foundRuntimeVersion = $toolchainVersion
            }
        }
        if (-not $foundRuntime) {
            $hit = Get-ChildItem -Path $runtimesRoot -Directory -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $runtimeBin = Join-Path $_.FullName "usr\bin"
                    if (Test-Path (Join-Path $runtimeBin "swiftCore.dll")) {
                        [PSCustomObject]@{ Path = $runtimeBin; Version = $_.Name }
                    }
                } |
                Select-Object -First 1
            if ($hit) {
                $foundRuntime = $hit.Path
                $foundRuntimeVersion = $hit.Version
            }
        }
    }
}

# Final fallback: use another installed runtime if no matching one was found.
if (-not $foundRuntime -and $toolchainVersion) {
    foreach ($dir in $runtimeDirs) {
        $searched += $dir
        if (Test-Path $dir) {
            $subdirs = Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue
            foreach ($subdir in $subdirs) {
                $candidate = Join-Path $subdir.FullName "usr\bin\swiftCore.dll"
                if (Test-Path $candidate) {
                    $foundRuntime = Join-Path $subdir.FullName "usr\bin"
                    $foundRuntimeVersion = $subdir.Name
                    break
                }
            }
        }
        if ($foundRuntime) { break }
    }
}

if (-not $foundRuntime) {
    Write-Host "Warning: Swift Runtime not found. Searched:"
    $searched | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

if ($toolchainVersion -and $foundRuntimeVersion -ne $toolchainVersion) {
    Write-Warning "No Swift runtime matching toolchain version $toolchainVersion was found; falling back to runtime version $foundRuntimeVersion."
}

if (-not $foundRuntimeVersion) {
    $foundRuntimeVersion = "unknown"
}
Write-Host "Selected Swift Runtime: $foundRuntime (version: $foundRuntimeVersion)"

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
