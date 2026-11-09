@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Turniket koprigi - avtomatik ishga tushirishni yoqish
set "BAT=%~dp03-ISHGA-TUSHIRISH.bat"
set "DIR=%~dp0"
echo.
echo Kompyuter yoqilganda (Windows ga kirilganda) turniket koprigi O'ZI ishga tushadigan qilinmoqda...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=[Environment]::GetFolderPath('Startup')+'\Turniket koprigi.lnk'; $s=(New-Object -ComObject WScript.Shell).CreateShortcut($p); $s.TargetPath=$env:BAT; $s.WorkingDirectory=$env:DIR; $s.WindowStyle=7; $s.Description='Turniket koprigi - Yuksalish platformasi'; $s.Save(); if(Test-Path $p){exit 0}else{exit 1}"
if errorlevel 1 (
  echo.
  echo XATO: avtomatik ishga tushirishni yoqib bo'lmadi. Bu oynani rasmga olib, administratorga yuboring.
  echo.
  pause
  exit /b 1
)
echo  [OK] Avtomatik ishga tushirish yoqildi.
echo.
echo Kompyuter uxlab qolmasligi uchun uyqu rejimi o'chirilmoqda (elektr tarmog'ida)...
powercfg /change standby-timeout-ac 0 >nul 2>&1
powercfg /change hibernate-timeout-ac 0 >nul 2>&1
echo  [OK] Tayyor.
echo.
echo Endi kompyuter har safar yoqilganda turniket koprigi o'zi ishga tushadi (pastki panelda kichraytirilgan oyna).
echo O'chirish kerak bo'lsa: 5-AVTOMATIKNI-OCHIRISH.bat
echo.
set /p H=Koprikni hozir ishga tushiraymi? (H/Y): 
if /i "%H%"=="H" start "" /min "%BAT%"
echo.
pause
