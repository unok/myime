@echo off
setlocal

echo ==============================================
echo MyIme Test Program
echo ==============================================
echo.

set "ROOT_DIR=%~dp0"
set "TEST_DIR=%ROOT_DIR%test"
set "BUILD_DIR=%ROOT_DIR%build\x64\release"

:: Check if build directory exists
if not exist "%BUILD_DIR%\azookey-engine.dll" (
    echo ERROR: azookey-engine.dll not found in %BUILD_DIR%
    echo Please run 'build-all.bat' first.
    exit /b 1
)

:: Check if config.json exists
if not exist "%ROOT_DIR%config.json" (
    echo ERROR: config.json not found
    echo Please run 'setup-dictionaries.bat' first.
    exit /b 1
)

:: Create test directory
if not exist "%TEST_DIR%" mkdir "%TEST_DIR%"

:: Create test program
echo Creating test program...
set "TEST_FILE=%TEST_DIR%\TestIme.cs"

echo using System; > "%TEST_FILE%"
echo using System.IO; >> "%TEST_FILE%"
echo using System.Runtime.InteropServices; >> "%TEST_FILE%"
echo using System.Text.Json; >> "%TEST_FILE%"
echo. >> "%TEST_FILE%"
echo namespace TestIme >> "%TEST_FILE%"
echo { >> "%TEST_FILE%"
echo     class Program >> "%TEST_FILE%"
echo     { >> "%TEST_FILE%"
echo         [DllImport("azookey-engine.dll", CallingConvention = CallingConvention.Cdecl)] >> "%TEST_FILE%"
echo         static extern IntPtr azookey_create(string configJson); >> "%TEST_FILE%"
echo. >> "%TEST_FILE%"
echo         [DllImport("azookey-engine.dll", CallingConvention = CallingConvention.Cdecl)] >> "%TEST_FILE%"
echo         static extern void azookey_destroy(IntPtr engine); >> "%TEST_FILE%"
echo. >> "%TEST_FILE%"
echo         [DllImport("azookey-engine.dll", CallingConvention = CallingConvention.Cdecl)] >> "%TEST_FILE%"
echo         static extern IntPtr azookey_convert(IntPtr engine, string input); >> "%TEST_FILE%"
echo. >> "%TEST_FILE%"
echo         [DllImport("azookey-engine.dll", CallingConvention = CallingConvention.Cdecl)] >> "%TEST_FILE%"
echo         static extern void azookey_free_string(IntPtr str); >> "%TEST_FILE%"
echo. >> "%TEST_FILE%"
echo         static void Main() >> "%TEST_FILE%"
echo         { >> "%TEST_FILE%"
echo             Console.WriteLine("=== MyIme Test Program ===\n"); >> "%TEST_FILE%"
echo. >> "%TEST_FILE%"
echo             try >> "%TEST_FILE%"
echo             { >> "%TEST_FILE%"
echo                 // Load configuration >> "%TEST_FILE%"
echo                 string configPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "config.json"); >> "%TEST_FILE%"
echo                 string configJson = File.ReadAllText(configPath); >> "%TEST_FILE%"
echo                 Console.WriteLine("Loaded config.json"); >> "%TEST_FILE%"
echo. >> "%TEST_FILE%"
echo                 // Create engine >> "%TEST_FILE%"
echo                 IntPtr engine = azookey_create(configJson); >> "%TEST_FILE%"
echo                 if (engine == IntPtr.Zero) >> "%TEST_FILE%"
echo                 { >> "%TEST_FILE%"
echo                     Console.WriteLine("ERROR: Failed to create engine"); >> "%TEST_FILE%"
echo                     return; >> "%TEST_FILE%"
echo                 } >> "%TEST_FILE%"
echo                 Console.WriteLine("Created AzooKey engine\n"); >> "%TEST_FILE%"
echo. >> "%TEST_FILE%"
echo                 // Test conversions >> "%TEST_FILE%"
echo                 string[] testInputs = { >> "%TEST_FILE%"
echo                     "konnichiha", >> "%TEST_FILE%"
echo                     "arigatou", >> "%TEST_FILE%"
echo                     "ohayougozaimasu", >> "%TEST_FILE%"
echo                     "sayounara", >> "%TEST_FILE%"
echo                     "nihongo" >> "%TEST_FILE%"
echo                 }; >> "%TEST_FILE%"
echo. >> "%TEST_FILE%"
echo                 Console.WriteLine("Testing conversions:"); >> "%TEST_FILE%"
echo                 Console.WriteLine("-------------------"); >> "%TEST_FILE%"
echo. >> "%TEST_FILE%"
echo                 foreach (string input in testInputs) >> "%TEST_FILE%"
echo                 { >> "%TEST_FILE%"
echo                     IntPtr resultPtr = azookey_convert(engine, input); >> "%TEST_FILE%"
echo                     if (resultPtr != IntPtr.Zero) >> "%TEST_FILE%"
echo                     { >> "%TEST_FILE%"
echo                         string result = Marshal.PtrToStringUTF8(resultPtr); >> "%TEST_FILE%"
echo                         Console.WriteLine($"{input} -> {result}"); >> "%TEST_FILE%"
echo                         azookey_free_string(resultPtr); >> "%TEST_FILE%"
echo                     } >> "%TEST_FILE%"
echo                     else >> "%TEST_FILE%"
echo                     { >> "%TEST_FILE%"
echo                         Console.WriteLine($"{input} -> (conversion failed)"); >> "%TEST_FILE%"
echo                     } >> "%TEST_FILE%"
echo                 } >> "%TEST_FILE%"
echo. >> "%TEST_FILE%"
echo                 // Clean up >> "%TEST_FILE%"
echo                 azookey_destroy(engine); >> "%TEST_FILE%"
echo                 Console.WriteLine("\nEngine destroyed successfully"); >> "%TEST_FILE%"
echo             } >> "%TEST_FILE%"
echo             catch (Exception ex) >> "%TEST_FILE%"
echo             { >> "%TEST_FILE%"
echo                 Console.WriteLine($"ERROR: {ex.Message}"); >> "%TEST_FILE%"
echo                 Console.WriteLine($"Stack trace: {ex.StackTrace}"); >> "%TEST_FILE%"
echo             } >> "%TEST_FILE%"
echo. >> "%TEST_FILE%"
echo             Console.WriteLine("\nPress any key to exit..."); >> "%TEST_FILE%"
echo             Console.ReadKey(); >> "%TEST_FILE%"
echo         } >> "%TEST_FILE%"
echo     } >> "%TEST_FILE%"
echo } >> "%TEST_FILE%"

:: Create project file
set "PROJ_FILE=%TEST_DIR%\TestIme.csproj"
echo ^<Project Sdk="Microsoft.NET.Sdk"^> > "%PROJ_FILE%"
echo   ^<PropertyGroup^> >> "%PROJ_FILE%"
echo     ^<OutputType^>Exe^</OutputType^> >> "%PROJ_FILE%"
echo     ^<TargetFramework^>net8.0^</TargetFramework^> >> "%PROJ_FILE%"
echo     ^<Nullable^>enable^</Nullable^> >> "%PROJ_FILE%"
echo     ^<AllowUnsafeBlocks^>true^</AllowUnsafeBlocks^> >> "%PROJ_FILE%"
echo   ^</PropertyGroup^> >> "%PROJ_FILE%"
echo ^</Project^> >> "%PROJ_FILE%"

:: Build test program
echo.
echo Building test program...
cd /d "%TEST_DIR%"
dotnet build --configuration Release
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to build test program
    exit /b 1
)

:: Copy required files to test output directory
echo.
echo Copying required files...
set "TEST_OUTPUT=%TEST_DIR%\bin\Release\net8.0"
xcopy /y "%BUILD_DIR%\*.dll" "%TEST_OUTPUT%\" >nul
xcopy /y "%ROOT_DIR%config.json" "%TEST_OUTPUT%\..\..\.." >nul

:: Run test program
echo.
echo Running test program...
echo ==============================================
echo.
cd /d "%TEST_OUTPUT%"
chcp 65001 >nul
TestIme.exe

endlocal
exit /b %ERRORLEVEL%