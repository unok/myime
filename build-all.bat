@echo off
setlocal

echo ==============================================
echo Building MyIme - Full Build
echo ==============================================
echo.

set "ROOT_DIR=%~dp0"

:: Build Swift Engine
echo [1/2] Building Swift Engine...
echo ----------------------------------------------
call "%ROOT_DIR%build-swift-final.bat"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Swift build failed
    exit /b 1
)

:: Build C# IME
echo.
echo [2/2] Building C# IME...
echo ----------------------------------------------

:: Check if .NET SDK is installed
where dotnet >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: .NET SDK is not installed or not in PATH
    echo Please install .NET 8.0 SDK and try again.
    exit /b 1
)

:: Change to C# project directory
cd /d "%ROOT_DIR%src\csharp-ime"

:: Restore NuGet packages
echo Restoring NuGet packages...
dotnet restore MyIme.sln
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to restore NuGet packages
    exit /b 1
)

:: Build the solution
echo Building C# solution...
dotnet build MyIme.sln --configuration Release
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: C# build failed
    exit /b 1
)

:: Copy C# outputs to build directory
echo.
echo Copying C# outputs...
set "CS_OUTPUT_DIR=%ROOT_DIR%build\x64\release"
if not exist "%CS_OUTPUT_DIR%" mkdir "%CS_OUTPUT_DIR%"

:: Copy Core library
xcopy /y "%ROOT_DIR%src\csharp-ime\MyIme.Core\bin\Release\net8.0\*.*" "%CS_OUTPUT_DIR%\" >nul
echo Copied: MyIme.Core assemblies

:: Copy TSF library
xcopy /y "%ROOT_DIR%src\csharp-ime\MyIme.Tsf\bin\Release\net8.0-windows\*.*" "%CS_OUTPUT_DIR%\" >nul
echo Copied: MyIme.Tsf assemblies

echo.
echo ==============================================
echo Build completed successfully!
echo ==============================================
echo.
echo Output directory: %CS_OUTPUT_DIR%
echo.
echo Next steps:
echo 1. Run 'test-ime.bat' to test the IME
echo 2. Run registration script to install the IME
echo.

endlocal
exit /b 0