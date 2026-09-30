@echo off
setlocal EnableExtensions
REM deepDesign Studio - Windows release build + packaging (dev.bat = debug run; this = release bundle)
REM Usage: build.bat
REM Output: src-tauri\target\release\bundle\nsis\*.exe (installer)
REM         src-tauri\target\release\deepdesign-studio.exe (bare binary)
set "ROOT=%~dp0"

where node >nul 2>nul
if errorlevel 1 (
  echo [build.bat] node not found - tauri CLI and engine sync both need it
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
    echo [build.bat] GNU toolchain detected - using MSVC for this build
  )
)

REM Engine artifact: tauri build's beforeBuildCommand syncs it too; pre-check gives a
REM clearer error when offline and the artifact is absent (sync needs GitHub connectivity)
if not exist "%ROOT%frontend\vendor\moonviz.wasm" (
  echo [build.bat] engine wasm missing - syncing via node scripts\sync-engine.mjs ...
  pushd "%ROOT%"
  call node scripts\sync-engine.mjs || (popd & echo [build.bat] engine sync failed & exit /b 1)
  popd
)

REM tauri CLI probe: global tauri -> npx
set "TAURI_CMD="
where tauri >nul 2>nul
if not errorlevel 1 (
  set "TAURI_CMD=tauri"
) else (
  echo [build.bat] global tauri CLI not found - using npx @tauri-apps/cli
)

echo [build.bat] release build + packaging ... (first run can take several minutes)
pushd "%ROOT%"
if defined TAURI_CMD (
  call tauri build
) else (
  call npx @tauri-apps/cli build
)
set "RC=%errorlevel%"
popd
if not "%RC%"=="0" (
  echo [build.bat] build failed
  endlocal & exit /b %RC%
)

echo [build.bat] done. artifacts:
if exist "%ROOT%src-tauri\target\release\bundle\nsis\" dir /b "%ROOT%src-tauri\target\release\bundle\nsis\*.exe"
if exist "%ROOT%src-tauri\target\release\deepdesign-studio.exe" echo   binary: src-tauri\target\release\deepdesign-studio.exe
endlocal & exit /b 0
