# Build script for MyIme
$ErrorActionPreference = "Stop"

Write-Host "Building MyIme..." -ForegroundColor Cyan

# Build Swift engine
Write-Host "`nBuilding Swift engine..." -ForegroundColor Green
Set-Location "$PSScriptRoot\src\swift-engine"

$swiftExe = "C:\Users\unok\AppData\Local\Programs\Swift\Toolchains\6.2.1+Asserts\usr\bin\swift.exe"
& $swiftExe build -c release --product azookey-engine

if ($LASTEXITCODE -ne 0) {
    Write-Host "Swift build failed!" -ForegroundColor Red
    exit 1
}

# Copy Swift DLL
$outputDir = "$PSScriptRoot\build\x64\release"
if (!(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

Copy-Item ".build\x86_64-unknown-windows-msvc\release\azookey-engine.dll" $outputDir -Force

# Copy Swift runtime DLLs
$runtimePath = "C:\Users\unok\AppData\Local\Programs\Swift\Runtimes\6.2.1\usr\bin"
Copy-Item "$runtimePath\*.dll" $outputDir -Force

# Build C# IME
Write-Host "`nBuilding C# IME..." -ForegroundColor Green
Set-Location "$PSScriptRoot\src\csharp-ime"
dotnet build -c Release

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nBuild completed successfully!" -ForegroundColor Green
    Write-Host "Output: $outputDir" -ForegroundColor Cyan
} else {
    Write-Host "`nC# build failed!" -ForegroundColor Red
    exit 1
}