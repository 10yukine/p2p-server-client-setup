@echo off
setlocal
cd /d "%SystemRoot%"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "%~dp0_assets\Setup-GUI.ps1"
if errorlevel 1 pause
