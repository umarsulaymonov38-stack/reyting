@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=[Environment]::GetFolderPath('Startup')+'\Turniket koprigi.lnk'; if(Test-Path $p){Remove-Item $p}"
echo Avtomatik ishga tushirish o'chirildi. Koprikni endi 3-ISHGA-TUSHIRISH.bat bilan qo'lda ishga tushirasiz.
echo.
pause
