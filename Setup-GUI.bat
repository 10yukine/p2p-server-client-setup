@echo off
setlocal
title P2P Server Client Setup
echo Checking Windows compatibility and looking for drives and Ethernet adapters.
echo Please wait. These checks may take a moment before the setup window appears.
echo.
set "P2P_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "P2P_POWERSHELL=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%P2P_POWERSHELL%" (
    echo Windows PowerShell is missing. Restore it before running this helper.
    pause
    exit /b 1
)
cd /d "%SystemRoot%"
"%P2P_POWERSHELL%" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0_assets\Setup-GUI.ps1"
if errorlevel 1 (
    pause
    exit /b 1
)
