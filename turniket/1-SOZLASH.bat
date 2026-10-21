@echo off
chcp 65001 >nul
cd /d "%~dp0"
python turniket_bridge.py --setup
echo.
pause
