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
    echo Skipped: azooKey_dictionary_storage (already exists)
)

git submodule add https://github.com/azooKey/azooKey_emoji_dictionary_storage.git dictionaries/azooKey_emoji_dictionary_storage 2>nul
if %ERRORLEVEL% EQU 0 (
    echo Added: azooKey_emoji_dictionary_storage
) else (
    echo Skipped: azooKey_emoji_dictionary_storage (already exists)
)

echo.
echo Updating submodules...
git submodule update --init --recursive

:: Create config.json
echo.
echo Creating default configuration...
set "CONFIG_FILE=%ROOT_DIR%config.json"

echo { > "%CONFIG_FILE%"
echo   "dictionaryPath": "%DICT_DIR:\=\\%\\azooKey_dictionary_storage", >> "%CONFIG_FILE%"
echo   "memoryPath": "%ROOT_DIR:\=\\%\\userdata\\memory", >> "%CONFIG_FILE%"
echo   "zenzaiEnabled": false, >> "%CONFIG_FILE%"
echo   "zenzaiInferenceLimit": 10, >> "%CONFIG_FILE%"
echo   "zenzaiWeightPath": "" >> "%CONFIG_FILE%"
echo } >> "%CONFIG_FILE%"

echo Created: config.json

:: Create userdata directory
set "USERDATA_DIR=%ROOT_DIR%userdata\memory"
if not exist "%USERDATA_DIR%" mkdir "%USERDATA_DIR%"

echo.
echo ==============================================
echo Dictionary setup completed!
echo ==============================================
echo.
echo Next steps:
echo 1. For Zenzai support, download the model weights
echo 2. Update config.json with the model path
echo 3. Set zenzaiEnabled to true
echo.

pause
endlocal