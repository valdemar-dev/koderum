@echo off
setlocal enabledelayedexpansion

if "%~1"=="" (
    echo Usage: %~nx0 ^<version^>
    exit /b 1
)

set VERSION=%~1
set RELEASE_DIR=.\releases
set OUTPUT=%RELEASE_DIR%\koderum_%VERSION%.zip

if not exist "%RELEASE_DIR%" (
    mkdir "%RELEASE_DIR%"
)

odin build src -o:speed -out:koderum.exe
if errorlevel 1 exit /b %errorlevel%

powershell -NoLogo -NoProfile -Command ^
    "Compress-Archive -Path 'koderum.exe','.\languages','.\config' -DestinationPath '%OUTPUT%' -Force"
if errorlevel 1 exit /b %errorlevel%

