@echo off
cd /d "%~dp0"
echo Rebuilding Swift engine...
cd src\swift-engine
swift build -c release
echo.
echo Copying DLL...
copy /y .build\release\azookey-engine.dll ..\..\build\x64\release\
copy /y .build\release\azookey-engine.dll ..\..\test\bin\Release\net8.0\
copy /y .build\release\azookey-engine.dll ..\..\test-detection\bin\Release\net8.0\
echo Done.