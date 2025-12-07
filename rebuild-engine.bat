@echo off
cd /d "%~dp0"
echo Rebuilding Swift engine with debug logs...
call build-swift-standalone.bat
echo.
echo Copying new DLL to test directories...
copy /y build\x64\release\azookey-engine.dll test\bin\Release\net8.0\
copy /y build\x64\release\azookey-engine.dll test-detection\bin\Release\net8.0\
echo Done.