@echo off
setlocal

setlocal ENABLEDELAYEDEXPANSION

SET BASEDIR=%~dp0

REM Refuse to write a runner package unless CMake supplied an isolated directory.
REM An unset variable or failed cd would otherwise overwrite the app pubspec.
if not defined CARGOKIT_TOOL_TEMP_DIR (
    echo CARGOKIT_TOOL_TEMP_DIR must be set by the build system. 1>&2
    exit /b 1
)
if not defined FLUTTER_ROOT (
    echo FLUTTER_ROOT must point to the Flutter SDK. 1>&2
    exit /b 1
)

if not exist "%CARGOKIT_TOOL_TEMP_DIR%" (
    mkdir "%CARGOKIT_TOOL_TEMP_DIR%"
    if errorlevel 1 exit /b 1
)
cd /D "%CARGOKIT_TOOL_TEMP_DIR%"
if errorlevel 1 exit /b 1

REM Never replace a real application/package manifest on a misconfigured run.
if exist pubspec.yaml (
    findstr /X /C:"name: build_tool_runner" pubspec.yaml >nul
    if errorlevel 1 (
        echo Refusing to overwrite an existing package in the build tool directory. 1>&2
        exit /b 1
    )
)

SET BUILD_TOOL_PKG_DIR=%BASEDIR%build_tool
SET DART=%FLUTTER_ROOT%\bin\cache\dart-sdk\bin\dart

set BUILD_TOOL_PKG_DIR_POSIX=%BUILD_TOOL_PKG_DIR:\=/%

(
    echo name: build_tool_runner
    echo version: 1.0.0
    echo publish_to: none
    echo.
    echo environment:
    echo   sdk: '^>=3.0.0 ^<4.0.0'
    echo.
    echo dependencies:
    echo   build_tool:
    echo     path: %BUILD_TOOL_PKG_DIR_POSIX%
) >pubspec.yaml

if not exist bin (
    mkdir bin
)

(
    echo import 'package:build_tool/build_tool.dart' as build_tool;
    echo void main^(List^<String^> args^) ^{
    echo    build_tool.runMain^(args^);
    echo ^}
) >bin\build_tool_runner.dart

SET PRECOMPILED=bin\build_tool_runner.dill

REM To detect changes in package we compare output of DIR /s (recursive)
set PREV_PACKAGE_INFO=.dart_tool\package_info.prev
set CUR_PACKAGE_INFO=.dart_tool\package_info.cur

DIR "%BUILD_TOOL_PKG_DIR%" /s > "%CUR_PACKAGE_INFO%_orig"

REM Last line in dir output is free space on harddrive. That is bound to
REM change between invocation so we need to remove it
(
    Set "Line="
    For /F "UseBackQ Delims=" %%A In ("%CUR_PACKAGE_INFO%_orig") Do (
        SetLocal EnableDelayedExpansion
        If Defined Line Echo !Line!
        EndLocal
        Set "Line=%%A")
) >"%CUR_PACKAGE_INFO%"
DEL "%CUR_PACKAGE_INFO%_orig"

REM Compare current directory listing with previous
FC /B "%CUR_PACKAGE_INFO%" "%PREV_PACKAGE_INFO%" > nul 2>&1

If %ERRORLEVEL% neq 0 (
    REM Changed - copy current to previous and remove precompiled kernel
    if exist "%PREV_PACKAGE_INFO%" (
        DEL "%PREV_PACKAGE_INFO%"
    )
    MOVE /Y "%CUR_PACKAGE_INFO%" "%PREV_PACKAGE_INFO%"
    if exist "%PRECOMPILED%" (
        DEL "%PRECOMPILED%"
    )
)

REM There is no CUR_PACKAGE_INFO it was renamed in previous step to %PREV_PACKAGE_INFO%
REM which means  we need to do pub get and precompile
if not exist "%PRECOMPILED%" (
    echo Running pub get in "%cd%"
    "%DART%" pub get --no-precompile
    if errorlevel 1 exit /b 1
    "%DART%" compile kernel bin/build_tool_runner.dart
    if errorlevel 1 exit /b 1
)

"%DART%" "%PRECOMPILED%" %*

REM 253 means invalid snapshot version.
If %ERRORLEVEL% equ 253 (
    "%DART%" pub get --no-precompile
    if errorlevel 1 exit /b 1
    "%DART%" compile kernel bin/build_tool_runner.dart
    if errorlevel 1 exit /b 1
    "%DART%" "%PRECOMPILED%" %*
)
