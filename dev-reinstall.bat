@echo off
setlocal EnableDelayedExpansion

:: ==============================================
:: MyIME 開発用 再インストール (再起動不要)
:: ==============================================
:: ビルド済み MSI を、IME プロセス/サービスを停止してから再インストールする。
:: このビルド(非Release)には ScheduleReboot が無いため、ロックさえ外せば
:: マシン再起動なしで何度でも入れ直せる。
::
:: 使い方:  dev-reinstall.bat            (既定の MSI を使用)
::          dev-reinstall.bat "msiパス"  (MSI を明示指定)
::
:: 注意: mozc_tip64.dll を読み込み済みの一般アプリ(エクスプローラ/ブラウザ等)が
::       起動したままだと、その DLL だけ「使用中」で置換できないことがある。
::       変換エンジン(azookey/mozc_server)の変更はサーバ停止で反映されるので
::       通常は問題ない。TIP 自体を変えた時は該当アプリを閉じること。
:: ==============================================

set "ROOT_DIR=%~dp0"

:: --- 管理者権限へ自己昇格 (msiexec とサービス操作に必要) ---
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo 管理者権限が必要です。昇格します...
    if "%~1"=="" (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs"
    )
    exit /b
)

:: --- MSI パス決定 ---
set "MSI=%~1"
if "%MSI%"=="" set "MSI=%ROOT_DIR%mozc\src\bazel-bin\win32\installer\Mozc_x64.msi"
if not exist "%MSI%" set "MSI=%ROOT_DIR%Mozc_x64.msi"
if not exist "%MSI%" (
    echo [ERROR] MSI が見つかりません: %MSI%
    echo   先に build-x64.bat を実行してください。
    pause
    exit /b 1
)
echo 使用する MSI: %MSI%

:: bazel-bin はシンボリックリンクで、その先は読み取り専用の Bazel キャッシュ。
:: Windows Installer サービス(SYSTEM)がリンク経由だと開けず error 1619 になるため、
:: 実体ファイルとして安定した場所へコピーしてからインストールする。
set "MSI_LOCAL=%SystemRoot%\Temp\Mozc_x64_dev.msi"
copy /y "%MSI%" "%MSI_LOCAL%" >nul 2>&1
if not exist "%MSI_LOCAL%" (
    echo [ERROR] MSI のコピーに失敗しました: %MSI_LOCAL%
    pause
    exit /b 1
)
echo インストール元: %MSI_LOCAL%
echo.

:: --- IME サービス/プロセスを停止してファイルロックを解放 ---
echo IME サービス/プロセスを停止しています...
sc stop MozcCacheService >nul 2>&1
taskkill /f /im mozc_server.exe        >nul 2>&1
taskkill /f /im mozc_renderer.exe      >nul 2>&1
taskkill /f /im mozc_broker.exe        >nul 2>&1
taskkill /f /im mozc_cache_service.exe >nul 2>&1
taskkill /f /im mozc_tool.exe          >nul 2>&1
taskkill /f /im ctfmon.exe             >nul 2>&1
:: サービス停止とハンドル解放を待つ (timeout は環境により GNU 版に食われるため ping を使用)
ping -n 3 127.0.0.1 >nul

:: --- 再インストール (REINSTALLMODE=vamus で全ファイル強制上書き) ---
echo MSI を再インストールしています...
msiexec /i "%MSI_LOCAL%" /qb REINSTALL=ALL REINSTALLMODE=vamus
set "RC=%ERRORLEVEL%"
if "%RC%"=="1638" (
    echo REINSTALL 不可。通常インストールで再試行します...
    msiexec /i "%MSI_LOCAL%" /qb
    set "RC=!ERRORLEVEL!"
)
if not "%RC%"=="0" if not "%RC%"=="3010" (
    echo [ERROR] msiexec が失敗しました (exit %RC%)
    pause
    exit /b %RC%
)

:: --- IPC キャッシュ掃除 & テキストサービス再起動 ---
echo IME を再起動しています...
del /q "%USERPROFILE%\AppData\LocalLow\Mozc\*.ipc" >nul 2>&1
start "" ctfmon.exe

echo.
echo ==============================================
echo 完了しました (再起動不要)。入力を試して変更を確認してください。
echo ==============================================
ping -n 3 127.0.0.1 >nul
endlocal
