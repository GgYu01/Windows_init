@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Resolve repo root based on script location.

set "SRC=%~dp0.."
for %%I in ("%SRC%") do set "SRC=%%~fI"

rem Target path is the extracted Windows media root.
set "TARGET=%~1"
if "%TARGET%"=="" goto :usage
for %%I in ("%TARGET%") do set "TARGET=%%~fI"

if not exist "%TARGET%" (
  echo [ERROR] Target path not found: "%TARGET%"
  exit /b 1
)

rem Minimal copy set: Autounattend + sources\Autounattend + Scripts tree.
set "SRC_AUTOUNATTEND=%SRC%\Autounattend.xml"
set "SRC_AUTOUNATTEND_SOURCES=%SRC%\sources\Autounattend.xml"
set "SRC_SCRIPTS=%SRC%\sources\$OEM$\$$\Setup\Scripts"

if not exist "%SRC_AUTOUNATTEND%" (
  echo [ERROR] Missing source file: "%SRC_AUTOUNATTEND%"
  exit /b 1
)
if not exist "%SRC_AUTOUNATTEND_SOURCES%" (
  echo [ERROR] Missing source file: "%SRC_AUTOUNATTEND_SOURCES%"
  exit /b 1
)
if not exist "%SRC_SCRIPTS%" (
  echo [ERROR] Missing source directory: "%SRC_SCRIPTS%"
  exit /b 1
)

if not exist "%TARGET%\sources" mkdir "%TARGET%\sources" >nul 2>&1
if not exist "%TARGET%\sources\$OEM$\$$\Setup\Scripts" mkdir "%TARGET%\sources\$OEM$\$$\Setup\Scripts" >nul 2>&1

copy /Y "%SRC_AUTOUNATTEND%" "%TARGET%\Autounattend.xml" >nul
copy /Y "%SRC_AUTOUNATTEND_SOURCES%" "%TARGET%\sources\Autounattend.xml" >nul

call :copy_tree "%SRC_SCRIPTS%" "%TARGET%\sources\$OEM$\$$\Setup\Scripts"

echo [INFO] Sync completed.
exit /b 0

:copy_tree
set "SRC_DIR=%~1"
set "DST_DIR=%~2"
where robocopy >nul 2>&1
if not errorlevel 1 (
  robocopy "%SRC_DIR%" "%DST_DIR%" /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
  exit /b %errorlevel%
)
xcopy "%SRC_DIR%\*" "%DST_DIR%\" /E /I /H /Y >nul
exit /b %errorlevel%

:usage
echo Usage: %~nx0 ^<ISO_ROOT^>
echo Example: %~nx0 D:\WinISO
exit /b 2
