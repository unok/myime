@echo off
echo Starting build...
echo.

set VCVARS="C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"

if not exist %VCVARS% (
    echo vcvars64.bat not found at default location
    exit /b 1
)

call %VCVARS%

cd /d "C:\Users\unok\git\myime\tests"

echo Compiling zenzai_test.cpp...
cl.exe /nologo /EHsc /O2 /Fe:zenzai_test.exe zenzai_test.cpp

if exist zenzai_test.exe (
    echo.
    echo Build successful. Running test...
    echo.
    zenzai_test.exe
) else (
    echo Build failed.
)
