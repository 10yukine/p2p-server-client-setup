@echo off
setlocal
title P2P Server Client Setup
echo Checking Windows compatibility and looking for drives and Ethernet adapters.
echo Please wait. These checks may take a moment before the setup window appears.
echo.
cd /d "%SystemRoot%"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0_assets\Setup-GUI.ps1"
if errorlevel 1 pause
