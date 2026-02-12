@echo off
REM Wrapper to run build-x64.bat with low priority
start "MyIME Build" /belownormal /wait cmd /c "%~dp0build-x64.bat"
