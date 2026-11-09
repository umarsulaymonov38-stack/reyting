@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Turniket - o'tishlarni qayta yuklash
echo Turniket xotirasidagi o'tishlarni platformaga qayta yuboradi (avval kelganlari takrorlanmaydi).
echo Ishlab turgan ko'prikni yopish SHART EMAS.
echo.
set /p S=Qaysi sanadan beri? (masalan 2026-11-09, bugun uchun shunchaki Enter): 
if "%S%"=="" for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set S=%%d
python turniket_bridge.py --since %S%
echo.
pause
