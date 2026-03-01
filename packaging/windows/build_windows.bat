@echo off
REM Build script for VibeToText on Windows
REM Run from the project root: packaging\windows\build_windows.bat
REM
REM Usage:
REM   packaging\windows\build_windows.bat            - Build executables only
REM   packaging\windows\build_windows.bat installer  - Build executables + Inno Setup installer
REM
REM Prerequisites:
REM   - Python 3.10+
REM   - For installer: Inno Setup 6.x (iscc.exe in PATH)

echo === Building VibeToText for Windows ===
echo.

REM Check if Python is available
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python not found. Please install Python 3.10+ and add to PATH.
    exit /b 1
)

REM Create virtual environment if it doesn't exist
if not exist ".venv" (
    echo Creating virtual environment...
    python -m venv .venv
)

REM Activate virtual environment
call .venv\Scripts\activate.bat

REM Install the package with all dependencies
echo Installing dependencies...
pip install -e ".[windows,gemini,build]" --quiet
if errorlevel 1 (
    echo ERROR: Failed to install dependencies.
    exit /b 1
)

REM Download whisper model if needed
echo.
echo Checking whisper model...
python -c "from pywhispercpp.model import Model; Model('base')" 2>nul
if errorlevel 1 (
    echo Downloading whisper base model...
    python -c "from pywhispercpp.model import Model; Model('base')"
)

REM Build main engine
echo.
echo Building main engine executable...
pyinstaller packaging\windows\vibetotext-engine.spec --noconfirm --distpath dist --workpath pyinstaller_build
if errorlevel 1 (
    echo ERROR: Failed to build engine executable.
    exit /b 1
)

REM Build UI
echo.
echo Building UI overlay executable...
pyinstaller packaging\windows\vibetotext-ui.spec --noconfirm --distpath dist --workpath pyinstaller_build
if errorlevel 1 (
    echo ERROR: Failed to build UI executable.
    exit /b 1
)

echo.
echo === Executables built successfully! ===
echo   - dist\vibetotext-engine.exe
echo   - dist\vibetotext-ui.exe
echo.

REM Check if installer build was requested
if /i "%1"=="installer" (
    echo === Building installer ===
    echo.

    REM Check for Inno Setup
    where iscc >nul 2>&1
    if errorlevel 1 (
        echo WARNING: Inno Setup compiler ^(iscc.exe^) not found in PATH.
        echo Download from: https://jrsoftware.org/isinfo.php
        echo.
        echo Skipping installer build. Executables are still available in dist\.
        goto :done
    )

    REM Build the installer
    iscc packaging\windows\vibetotext-installer.iss
    if errorlevel 1 (
        echo ERROR: Installer build failed.
        exit /b 1
    )

    echo.
    echo === Installer built successfully! ===
    echo   - dist\VibeToText-Setup-0.1.0.exe
    echo.
)

:done
echo To run directly: dist\vibetotext-engine.exe
echo.
pause
