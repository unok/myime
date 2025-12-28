# Zenzai Test Build and Run Script

$ErrorActionPreference = "Stop"

Write-Host "============================================"
Write-Host "   Zenzai Integration Test - Build and Run"
Write-Host "============================================"
Write-Host ""

Set-Location $PSScriptRoot

# Find Visual Studio
$vsPath = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath

if (-not $vsPath) {
    Write-Host "[ERROR] Visual Studio not found"
    exit 1
}

Write-Host "Found Visual Studio: $vsPath"

# Use Developer Command Prompt via cmd
$vcvarsPath = "$vsPath\VC\Auxiliary\Build\vcvars64.bat"

Write-Host ""
Write-Host "--- Compiling test ---"

# Compile using cmd with vcvars
$compileCmd = "`"$vcvarsPath`" && cd /d `"$PSScriptRoot`" && cl.exe /nologo /EHsc /O2 /Fe:zenzai_test.exe zenzai_test.cpp 2>&1"
$compileResult = cmd /c $compileCmd

Write-Host $compileResult

if (-not (Test-Path "zenzai_test.exe")) {
    Write-Host "[ERROR] Compilation failed"
    exit 1
}

Write-Host ""
Write-Host "--- Running test ---"
Write-Host ""

# Run the test
& ".\zenzai_test.exe"
$testResult = $LASTEXITCODE

Write-Host ""
if ($testResult -eq 0) {
    Write-Host "[SUCCESS] All tests passed" -ForegroundColor Green
} else {
    Write-Host "[FAILURE] Some tests failed" -ForegroundColor Red
}

exit $testResult
