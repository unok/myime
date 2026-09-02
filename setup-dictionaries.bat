@echo off
setlocal

echo ==============================================
echo Dictionary Setup for MyIme
echo ==============================================
echo.

set "ROOT_DIR=%~dp0"
set "DICT_DIR=%ROOT_DIR%dictionaries"

:: Create directories
if not exist "%DICT_DIR%" mkdir "%DICT_DIR%"

echo Checking for AzooKey dictionary submodules...
cd /d "%ROOT_DIR%"

:: Check if git is available
where git >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Git is not installed or not in PATH
    echo Please install Git and try again.
    exit /b 1
)

:: Add dictionary submodules
echo.
echo Adding dictionary submodules...

git submodule add https://github.com/azooKey/azooKey_dictionary_storage.git dictionaries/azooKey_dictionary_storage 2>nul
if %ERRORLEVEL% EQU 0 (
    echo Added: azooKey_dictionary_storage
) else (
    echo Skipped: azooKey_dictionary_storage ^(already exists^)
)

git submodule add https://github.com/azooKey/azooKey_emoji_dictionary_storage.git dictionaries/azooKey_emoji_dictionary_storage 2>nul
if %ERRORLEVEL% EQU 0 (
    echo Added: azooKey_emoji_dictionary_storage
) else (
    echo Skipped: azooKey_emoji_dictionary_storage ^(already exists^)
)

echo.
echo Updating submodules...
git submodule update --init --recursive

echo.
echo ==============================================
echo Dictionary setup completed!
echo ==============================================
echo.
echo For Zenzai support, run download-zenzai-model.bat and enable Zenzai in the settings dialog.
echo.

pause
endlocal
