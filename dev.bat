@echo off
setlocal EnableExtensions
REM deepDesign Studio - Windows CMD launcher (equivalent of dev.sh, no Git Bash needed)
REM Usage: dev.bat [--fresh]
REM   default : tauri dev (debug build + launch native client)
REM   --fresh : kill old instance + clear WebView2 HTTP cache, force latest frontend
REM NOTE: only HTTP cache subdirs are cleared; Local Storage (dd-recent-projects /
REM       apiKey slots) is never touched.
set "ROOT=%~dp0"

where node >nul 2>nul
if errorlevel 1 (
  echo [dev.bat] node not found - tauri CLI and engine sync both need it
  exit /b 1
)

REM Windows: tauri/webview2 + wasmtime static libs are MSVC-only; the default GNU
REM toolchain fails at link time - redirect for this process only, global default untouched
set "ACTIVE_TS="
where rustup >nul 2>nul
if not errorlevel 1 (
  for /f "delims=" %%i in ('rustup show active-toolchain 2^>nul') do set "ACTIVE_TS=%%i"
)
if defined ACTIVE_TS (
  echo %ACTIVE_TS%| findstr /c:"gnu" >nul 2>nul
  if not errorlevel 1 (
    set "RUSTUP_TOOLCHAIN=stable-x86_64-pc-windows-msvc"
    echo [dev.bat] GNU toolchain detected - using MSVC for this run
  )
)

REM Engine ships as prebuilt wasm (frontend\vendor\moonviz.wasm); fetch on demand
REM (needs GitHub connectivity). When present, tauri dev's beforeDevCommand only
REM runs the local contract probe - works offline.
if not exist "%ROOT%frontend\vendor\moonviz.wasm" (
  echo [dev.bat] engine wasm missing - syncing via node scripts\sync-engine.mjs ...
  pushd "%ROOT%"
  call node scripts\sync-engine.mjs || (popd & echo [dev.bat] engine sync failed & exit /b 1)
  popd
)
echo [dev.bat] engine artifact: frontend\vendor\moonviz.wasm

if /i "%~1"=="--fresh" (
  echo [dev.bat] --fresh: killing old instance + clearing WebView2 HTTP cache ...
  taskkill /f /im "deepdesign-studio.exe" >nul 2>nul
  timeout /t 1 /nobreak >nul 2>nul
  for %%D in ("Cache" "Code Cache" "GPUCache") do (
    if exist "%LOCALAPPDATA%\com.deepcode.deepdesign\EBWebView\Default\%%~D" rmdir /s /q "%LOCALAPPDATA%\com.deepcode.deepdesign\EBWebView\Default\%%~D" >nul 2>nul
  )
)

REM tauri CLI probe: global tauri -> npx
set "TAURI_CMD="
where tauri >nul 2>nul
if not errorlevel 1 (
  set "TAURI_CMD=tauri"
) else (
  echo [dev.bat] global tauri CLI not found - using npx @tauri-apps/cli
)

echo [dev.bat] debug build + launching deepDesign Studio
echo [dev.bat] note: tauri dev only watches src-tauri\; press Ctrl+R in the window after editing frontend\
pushd "%ROOT%"
if defined TAURI_CMD (
  call tauri dev
) else (
  call npx @tauri-apps/cli dev
)
set "RC=%errorlevel%"
popd
endlocal & exit /b %RC%
