@echo off
:: VPN 切换管理器 - 双击此文件启动
:: 会自动请求管理员权限

cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0vpn-switcher.ps1\"' -Verb RunAs"
