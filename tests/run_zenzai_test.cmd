@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" > nul 2>&1
cd /d C:\Users\unok\git\myime\tests
cl.exe /nologo /EHsc /O2 /Fe:zenzai_test.exe zenzai_test.cpp
if errorlevel 1 (
    echo Compilation failed
    exit /b 1
)
echo.
echo Running test...
echo.
zenzai_test.exe
