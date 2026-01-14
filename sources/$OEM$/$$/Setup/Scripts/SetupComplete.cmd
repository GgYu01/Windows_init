@echo off
setlocal EnableExtensions

REM Windows Setup runs %WINDIR%\Setup\Scripts\SetupComplete.cmd as SYSTEM after installation.
REM Use it as a reliable fallback trigger to start Windows_init at the first interactive logon.

set "LOG_ROOT=C:\ProgramData\WindowsInit\Logs"
set "PUBLIC_DEBUG=C:\Users\Public\Desktop\WindowsInit-Debug"
for /f %%i in ('powershell.exe -NoLogo -NoProfile -Command "(Get-Date).ToString('yyyyMMdd-HHmmss')"') do set "TS=%%i"
if not defined TS set "TS=unknown"

if not exist "%LOG_ROOT%" mkdir "%LOG_ROOT%" >nul 2>&1
if not exist "%PUBLIC_DEBUG%" mkdir "%PUBLIC_DEBUG%" >nul 2>&1
set "LOG_FILE=%LOG_ROOT%\SetupComplete-%TS%.log"

echo [INFO ] SetupComplete started at %DATE% %TIME% > "%LOG_FILE%"
echo [INFO ] Log file: %LOG_FILE% >> "%LOG_FILE%"

set "RUNONCE_KEY=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
set "ENTRY_NAME=WindowsInit-Phase0"
set "BOOTSTRAP=C:\Windows\Setup\Scripts\FirstLogonBootstrap.ps1"

echo [INFO ] Bootstrap path: %BOOTSTRAP% >> "%LOG_FILE%"

if not exist "%BOOTSTRAP%" (
  REM Nothing to do if the payload was not copied into the installed OS.
  echo [WARN ] Bootstrap script not found; skipping RunOnce registration. >> "%LOG_FILE%"
  copy "%LOG_FILE%" "%PUBLIC_DEBUG%\SetupComplete-%TS%.log" >nul 2>&1
  exit /b 0
)

REM Always (re)write the RunOnce entry; root.core.ps1 is idempotent via RootPhase>=2 and a mutex.
echo [INFO ] Writing RunOnce: %RUNONCE_KEY%\%ENTRY_NAME% >> "%LOG_FILE%"
reg add "%RUNONCE_KEY%" /v "%ENTRY_NAME%" /t REG_SZ /d "powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -File %BOOTSTRAP%" /f >> "%LOG_FILE%" 2>&1
echo [INFO ] reg add exit code: %ERRORLEVEL% >> "%LOG_FILE%"

copy "%LOG_FILE%" "%PUBLIC_DEBUG%\SetupComplete-%TS%.log" >nul 2>&1

exit /b 0
