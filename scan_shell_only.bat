@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0scan_shell_only.ps1" %*
pause
