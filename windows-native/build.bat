@echo off
echo ================================================
echo  VibeToText Windows - Build Script
echo ================================================
echo.

cd /d "%~dp0"

echo [1/3] Restoring NuGet packages...
dotnet restore src\VibeToText\VibeToText.csproj
if %errorlevel% neq 0 (
    echo ERROR: Package restore failed!
    pause
    exit /b 1
)

echo.
echo [2/3] Building project...
dotnet build src\VibeToText\VibeToText.csproj -c Release --no-restore
if %errorlevel% neq 0 (
    echo ERROR: Build failed!
    pause
    exit /b 1
)

echo.
echo [3/3] Publishing...
dotnet publish src\VibeToText\VibeToText.csproj -c Release -r win-x64 --self-contained -o dist
if %errorlevel% neq 0 (
    echo ERROR: Publish failed!
    pause
    exit /b 1
)

echo.
echo ================================================
echo  Build complete! Output in dist\
echo ================================================
echo.

if "%1"=="installer" (
    echo Building installer...
    where iscc >nul 2>&1
    if %errorlevel% equ 0 (
        iscc build\vibetotext-installer.iss
    ) else (
        echo Inno Setup not found. Install from https://jrsoftware.org/isinfo.php
    )
)

pause
