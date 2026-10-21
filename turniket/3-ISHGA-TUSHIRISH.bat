@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Turniket koprigi - YOPMANG
:qayta
python turniket_bridge.py
echo Dastur toxtadi, 10 soniyadan keyin qayta ishga tushadi...
timeout /t 10 >nul
goto qayta
