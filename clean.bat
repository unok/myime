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
echo Cleaning...

:: Shutdown Bazel server and clean workspace first (before deleting cache)
echo Stopping Bazel server and cleaning workspace...
pushd "%MOZC_SRC%"
where bazelisk >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    bazelisk shutdown 2>nul
    bazelisk clean --expunge 2>nul
    echo   Done.
) else (
    echo   Bazelisk not found, skipping.
)
popd

:: Clean Bazel user cache (after server is stopped)
echo Cleaning Bazel user cache...
set "BAZEL_USER_CACHE=%USERPROFILE%\_bazel_%USERNAME%"
if exist "%BAZEL_USER_CACHE%" (
    rmdir /s /q "%BAZEL_USER_CACHE%" 2>nul
    echo   Deleted %BAZEL_USER_CACHE%
) else (
    echo   No Bazel user cache found.
)

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
if exist "%SWIFT_DIR%\.swiftpm" (
    echo Cleaning Swift Package Manager cache...
    rmdir /s /q "%SWIFT_DIR%\.swiftpm" 2>nul
)

:: Clean output directories
set "OUTPUT_DIR_X64=%ROOT_DIR%build\x64\release"
set "OUTPUT_DIR_ARM64=%ROOT_DIR%build\arm64\release"
if exist "%OUTPUT_DIR_X64%" (
    echo Cleaning x64 output directory...
    rmdir /s /q "%OUTPUT_DIR_X64%" 2>nul
)
if exist "%OUTPUT_DIR_ARM64%" (
    echo Cleaning arm64 output directory...
    rmdir /s /q "%OUTPUT_DIR_ARM64%" 2>nul
)

:: Clean log files
echo Cleaning log files...
del /q "%ROOT_DIR%*.log" 2>nul

:: Clean MSI files
echo Cleaning MSI files...
del /q "%ROOT_DIR%*.msi" 2>nul

:: Clean llama.cpp build cache
echo Cleaning llama.cpp build cache...
if exist "%ROOT_DIR%llama.cpp-src" rmdir /s /q "%ROOT_DIR%llama.cpp-src" 2>nul
if exist "%ROOT_DIR%llama.cpp-build" rmdir /s /q "%ROOT_DIR%llama.cpp-build" 2>nul

:: Clean llama.cpp DLLs in lib directories
echo Cleaning llama.cpp DLLs...
del /q "%ROOT_DIR%src\AzooKeyKanaKanjiConverter\lib\windows\*.dll" 2>nul
del /q "%ROOT_DIR%src\AzooKeyKanaKanjiConverter\lib\windows\*.lib" 2>nul

echo.
echo ==============================================
echo Cleanup completed!
echo ==============================================
echo.
echo To rebuild from scratch, run: build-x64.bat
echo.

endlocal
exit /b 0
