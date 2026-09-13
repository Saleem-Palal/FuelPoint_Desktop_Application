@echo off
setlocal EnableExtensions
title FuelPoint Station OS Setup
cd /d "%~dp0"

net session >nul 2>&1
if %errorLevel% NEQ 0 (
  echo FuelPoint Station OS Setup
  echo.
  echo Windows will ask for Administrator permission.
  echo Click Yes so the certificate and the app can be installed.
  echo.
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -WorkingDirectory '%~dp0' -Verb RunAs"
  exit /b
)

echo.
echo FuelPoint Station OS Setup
echo Publisher: RetroSoft
echo.
echo Step 1 of 2  Installing RetroSoft certificate...
echo Step 2 of 2  Installing FuelPoint Station OS.msix...
echo.

if not exist "%~dp0install_fuelpoint_bundle.ps1" (
  echo Could not find install_fuelpoint_bundle.ps1
  echo Keep install.bat, FuelPointDevCert.cer, and "FuelPoint Station OS.msix" in the same folder.
  echo.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_fuelpoint_bundle.ps1"
exit /b %ERRORLEVEL%
