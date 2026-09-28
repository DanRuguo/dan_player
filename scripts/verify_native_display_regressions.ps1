[CmdletBinding()]
param(
    [string] $ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string] $OutputDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = Split-Path -Parent $ProjectRoot
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $workspace 'tool/qa-local/native-display-gate'
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$qaRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'tool/qa-local')) + [IO.Path]::DirectorySeparatorChar
if (-not $OutputDirectory.StartsWith($qaRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Native display fixtures must remain inside tool/qa-local.'
}
$flutter = Join-Path $workspace 'tool/flutter/bin/flutter.bat'
$oldTemp = $env:TEMP; $oldTmp = $env:TMP; $oldData = $env:DAN_PLAYER_DATA_DIR
try {
    $env:TEMP = Join-Path $OutputDirectory 'temp'; $env:TMP = $env:TEMP
    $env:DAN_PLAYER_DATA_DIR = Join-Path $OutputDirectory 'data'
    $null = New-Item -ItemType Directory -Force $env:TEMP, $env:DAN_PLAYER_DATA_DIR
    Push-Location $ProjectRoot
    try {
        # These failures require native shader/raster output. Widget coordinates
        # and software-rendered goldens cannot substitute for this gate.
        & $flutter build windows --profile --no-pub --target integration_test/text_motion_suite_test.dart `
            "--dart-define=DAN_TEXT_MOTION_RENDER=$OutputDirectory/text" `
            "--dart-define=DAN_DIALOG_FILTER_RENDER=$OutputDirectory/dialog" `
            "--dart-define=DAN_ENDPOINT_RENDER=$OutputDirectory/endpoints" *> (Join-Path $OutputDirectory 'build.log')
        if ($LASTEXITCODE -ne 0) { throw 'Native display regression build failed.' }
        & $flutter drive --profile --no-pub -d windows `
            --driver integration_test/edge_stretch_driver.dart `
            --target integration_test/text_motion_suite_test.dart `
            --use-application-binary (Join-Path $ProjectRoot 'build/windows/x64/runner/Profile/Dan Player.exe') `
            *> (Join-Path $OutputDirectory 'test.log')
        if ($LASTEXITCODE -ne 0) { throw 'Native display regressions failed; see test.log.' }
        & $flutter test --no-pub test/detail_timeline_practical_test.dart *> (Join-Path $OutputDirectory 'timeline.log')
        if ($LASTEXITCODE -ne 0) { throw 'Time preview regressions failed; see timeline.log.' }
    } finally { Pop-Location }
    Write-Host "Native display and time preview regressions passed: $OutputDirectory"
} finally {
    $env:TEMP = $oldTemp; $env:TMP = $oldTmp; $env:DAN_PLAYER_DATA_DIR = $oldData
}
