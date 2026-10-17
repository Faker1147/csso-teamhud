@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "SRC=%~dp0csso2_teamhud.sp"
set "OUT=%~dp0compiled\csso2_teamhud.smx"
if not exist "%~dp0compiled" mkdir "%~dp0compiled"

rem ==== 如果自动查找失败, 直接在这里写死 spcomp.exe 的完整路径 ====
set "SPC="

if not defined SPC (
  for %%P in (
    "D:\sourcemod-1.12.0-git7255-windows\addons\sourcemod\scripting\spcomp.exe"
    "C:\addons\sourcemod\scripting\spcomp.exe"
    "%ProgramFiles(x86)%\Steam\steamapps\common\Counter-Strike Global Offensive\csgo\addons\sourcemod\scripting\spcomp.exe"
    "D:\steamcmd\csgo\addons\sourcemod\scripting\spcomp.exe"
  ) do (
    if exist %%P set "SPC=%%~P"
  )
)

if not defined SPC (
  echo [ERROR] 没找到 spcomp.exe
  echo         请用记事本打开本文件, 把 SPC 改成 spcomp.exe 的完整路径。
  pause
  exit /b 1
)

echo 使用编译器: !SPC!
echo 编译: %SRC%
echo.

"!SPC!" "%SRC%" -o"%OUT%"

echo.
if exist "%OUT%" (
  echo [OK] 编译成功: %OUT%
  echo [提示] 把它复制到 addons\sourcemod\plugins\ 然后换图或执行 sm plugins load csso2_teamhud
) else (
  echo [FAIL] 编译失败, 请看上面的报错。
)

pause
