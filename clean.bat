@echo off
setlocal EnableDelayedExpansion

:: ==============================================
:: MyIME Clean Script (Bazel version)
:: ==============================================

set "ROOT_DIR=%~dp0"
set "MOZC_SRC=%ROOT_DIR%mozc\src"

echo ==============================================
echo MyIME Clean Script
echo ==============================================
echo.
echo This will remove build artifacts including:
echo   - Bazel build cache
echo   - Swift build directory
echo   - Output directory
echo   - Old ninja build directories
echo   - Log files
echo.

set /p "CONFIRM=Continue? (y/n): "
if /i not "%CONFIRM%"=="y" (
    echo Cancelled.
    exit /b 0
)

echo.
echo Cleaning...
echo.

:: Clean Bazel cache
echo Cleaning Bazel cache...
pushd "%MOZC_SRC%"
where bazelisk >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    bazelisk clean --expunge 2>nul
    echo   Done.
) else (
    echo   Bazelisk not found, skipping.
)
popd

:: Remove bazel symlinks
echo Removing Bazel symlinks...
if exist "%MOZC_SRC%\bazel-bin" rmdir "%MOZC_SRC%\bazel-bin" 2>nul
if exist "%MOZC_SRC%\bazel-out" rmdir "%MOZC_SRC%\bazel-out" 2>nul
if exist "%MOZC_SRC%\bazel-src" rmdir "%MOZC_SRC%\bazel-src" 2>nul
if exist "%MOZC_SRC%\bazel-testlogs" rmdir "%MOZC_SRC%\bazel-testlogs" 2>nul
if exist "%MOZC_SRC%\bazel-mozc" rmdir "%MOZC_SRC%\bazel-mozc" 2>nul

:: Clean Swift build
set "SWIFT_DIR=%ROOT_DIR%src\swift-engine"
if exist "%SWIFT_DIR%\.build" (
    echo Cleaning Swift build directory...
    rmdir /s /q "%SWIFT_DIR%\.build" 2>nul
)

:: Clean output directory
set "OUTPUT_DIR=%ROOT_DIR%build\x64\release"
if exist "%OUTPUT_DIR%" (
    echo Cleaning output directory...
    rmdir /s /q "%OUTPUT_DIR%" 2>nul
)

:: Clean old ninja build directories
if exist "%MOZC_SRC%\out_win" (
    echo Cleaning old ninja build directory...
    rmdir /s /q "%MOZC_SRC%\out_win" 2>nul
)

:: Clean log files
echo Cleaning log files...
del /q "%ROOT_DIR%*.log" 2>nul

:: Clean old directories
if exist "%ROOT_DIR%build-azookey" rmdir /s /q "%ROOT_DIR%build-azookey" 2>nul
if exist "%ROOT_DIR%build-azookey2" rmdir /s /q "%ROOT_DIR%build-azookey2" 2>nul
if exist "%ROOT_DIR%build-azookey3" rmdir /s /q "%ROOT_DIR%build-azookey3" 2>nul
if exist "%ROOT_DIR%build-reference" rmdir /s /q "%ROOT_DIR%build-reference" 2>nul
if exist "%ROOT_DIR%reference-ime" rmdir /s /q "%ROOT_DIR%reference-ime" 2>nul
if exist "%ROOT_DIR%test-comparison" rmdir /s /q "%ROOT_DIR%test-comparison" 2>nul
if exist "%ROOT_DIR%test-detection" rmdir /s /q "%ROOT_DIR%test-detection" 2>nul
if exist "%ROOT_DIR%test-incremental" rmdir /s /q "%ROOT_DIR%test-incremental" 2>nul
if exist "%ROOT_DIR%test-zenzai" rmdir /s /q "%ROOT_DIR%test-zenzai" 2>nul

echo.
echo ==============================================
echo Cleanup completed!
echo ==============================================
echo.
echo To rebuild from scratch, run: build.bat
echo.

endlocal
exit /b 0
