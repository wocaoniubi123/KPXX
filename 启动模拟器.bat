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
rem 服务在**最小化**窗口里跑（原来用 cmd /k 会留一个可见窗口）。要停服务：再跑一次本文件即可
rem —— 上面那段 netstat+taskkill 会先清掉占着 8787 的旧实例（server.mjs 不打请求日志，那个窗口没内容可看）。
start "" /min cmd /c ""%NODE%" server.mjs"

rem ⚠️ 2026-10-02 用户要求：不自动开浏览器（自己开 http://localhost:8787）；
rem 本启动器窗口在 start 之后**立刻 exit**，不 timeout、不 pause —— 不留任何等待。
exit
