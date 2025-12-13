@echo off
setlocal EnableExtensions

REM Windows Setup runs %WINDIR%\Setup\Scripts\SetupComplete.cmd as SYSTEM after installation.
REM Use it as a reliable fallback trigger to start Windows_init at the first interactive logon.

set "RUNONCE_KEY=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
set "ENTRY_NAME=WindowsInit-Phase0"
set "BOOTSTRAP=C:\Windows\Setup\Scripts\FirstLogonBootstrap.ps1"

if not exist "%BOOTSTRAP%" (
  REM Nothing to do if the payload was not copied into the installed OS.
  exit /b 0
)

REM Always (re)write the RunOnce entry; root.core.ps1 is idempotent via RootPhase>=2 and a mutex.
reg add "%RUNONCE_KEY%" /v "%ENTRY_NAME%" /t REG_SZ /d "powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -File %BOOTSTRAP%" /f >nul 2>&1

exit /b 0
