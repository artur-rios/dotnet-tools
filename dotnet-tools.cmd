@echo off
setlocal enabledelayedexpansion
REM Unified wrapper to dispatch to PowerShell command scripts
REM Usage: dotnet-tools <build|bump|clean|tag|test> [args]

set "SELF_DIR=%~dp0"
if "%~1"=="" goto :usage
set "SUB=%~1"
shift

if /I "%SUB%"=="build"  goto :do_build
if /I "%SUB%"=="bump"   goto :do_bump
if /I "%SUB%"=="clean"  goto :do_clean
if /I "%SUB%"=="tag"    goto :do_tag
if /I "%SUB%"=="test"   goto :do_test

echo [ERROR] Unknown command: %SUB%
goto :usage

:do_build
powershell -NoProfile -ExecutionPolicy Bypass -File "%SELF_DIR%commands\build.ps1" %*
exit /b %ERRORLEVEL%

:do_bump
powershell -NoProfile -ExecutionPolicy Bypass -File "%SELF_DIR%commands\bump.ps1" %*
exit /b %ERRORLEVEL%

:do_clean
powershell -NoProfile -ExecutionPolicy Bypass -File "%SELF_DIR%commands\clean.ps1" %*
exit /b %ERRORLEVEL%

:do_tag
powershell -NoProfile -ExecutionPolicy Bypass -File "%SELF_DIR%commands\tag.ps1" %*
exit /b %ERRORLEVEL%

:do_test
powershell -NoProfile -ExecutionPolicy Bypass -File "%SELF_DIR%commands\test.ps1" %*
exit /b %ERRORLEVEL%

:usage
echo Usage: dotnet-tools ^<command^> [args]
echo.
echo Commands:
echo   build  ^- Build a solution. Example: dotnet-tools build [path] [--no-restore] [--solution Name.sln] [--configuration Debug^|Release]
echo   bump   ^- Bump csproj ^<Version^>. Example: dotnet-tools bump --patch [path]
echo   clean  ^- Clean bin/ and obj/ under src. Example: dotnet-tools clean [path]
echo   tag    ^- Create git tag from csproj version. Example: dotnet-tools tag [path] [--push] [--remote origin]
echo   test   ^- Run tests and generate coverage. Example: dotnet-tools test [tests-path]
exit /b 1
