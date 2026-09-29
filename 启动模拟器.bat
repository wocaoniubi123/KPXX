@echo off
chcp 65001 >nul
title KPXX 模拟器
cd /d "%~dp0"

rem 找 node：PATH 里没有就用默认安装路径
set "NODE=node"
where node >nul 2>nul || set "NODE=C:\Program Files\nodejs\node.exe"

rem 先清掉可能残留的旧实例，避免 8787 端口被占
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":8787" ^| findstr LISTENING') do taskkill /F /PID %%p >nul 2>nul

echo.
echo   正在启动 KPXX 模拟器（数据/界面验证用）...
echo.

cd /d "%~dp0sim"
start "KPXX 模拟器服务（关掉此窗口即停止）" cmd /k ""%NODE%" server.mjs"

rem 用绝对路径调用 timeout.exe，避免被其它 PATH 里的同名程序顶掉
%SystemRoot%\System32\timeout.exe /t 2 /nobreak >nul
start "" http://localhost:8787

echo   浏览器已打开：http://localhost:8787
echo   服务在另一个窗口里跑，本窗口几秒后自动关闭。
%SystemRoot%\System32\timeout.exe /t 5 /nobreak >nul
exit
