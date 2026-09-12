#requires -Version 5.1
[CmdletBinding()]
param([string] $NativeDirectory, [switch] $ExpectLayoutFailure,
    [ValidateSet(7,9,11,14)][int[]] $FontSizes = @(7,9,11,14))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$renderRepository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$renderWorkspace = Split-Path -Parent $renderRepository
$setupText = [IO.File]::ReadAllText((Join-Path $renderRepository 'installer\setup.iss'))
if ($setupText -notmatch '(?m)^#define ProductionDialogFontSize 11\s*$' -or
    $setupText -notmatch '(?m)^DialogFontSize=\{#ProductionDialogFontSize\}\s*$') {
    throw 'Production installer must retain its audited 11 pt dialog baseline.'
}
if (-not $NativeDirectory) { $NativeDirectory = Join-Path $renderWorkspace 'tool\qa-installer\build\Release' }
$renderRoot = Join-Path $renderWorkspace ('tool\qa-installer\ui-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$null = New-Item -ItemType Directory -Path $renderRoot
$payload = Join-Path $renderRoot 'fictional-payload'
foreach ($relative in @('Dan Player.exe','data\app.so','desktop_lyric\desktop_lyric.exe','native_assets.json')) {
    $destination = Join-Path $payload $relative
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force
    [IO.File]::WriteAllText($destination, 'Fictional UI fixture; installed only in the QA sandbox, never executed.', [Text.UTF8Encoding]::new($false))
}
foreach ($theme in @('light','dark')) {
  foreach ($fontSize in $FontSizes) {
    $frames = Join-Path $renderRoot ($theme + '-font' + $fontSize)
    $null = New-Item -ItemType Directory -Path $frames
    $output = @(& (Join-Path $renderRepository 'scripts\build_windows_installer.ps1') -QaBuild -QaTheme $theme -QaDialogFontSize $fontSize -PayloadDirectory $payload -OutputRoot (Join-Path $renderRoot 'packages') -NativeDirectory $NativeDirectory)
    $package = $output | Where-Object { $_.PSObject.Properties.Name -contains 'Installer' } | Select-Object -Last 1
    if (-not $package) { throw 'QA UI package was not produced.' }
    $log = Join-Path $frames 'render.log'
    $target = Join-Path $frames 'fictional-install'
    $arguments = '"' + $package.Installer + '" "' + $target + '" "' + $log + '" render'
    $runner = Join-Path $NativeDirectory 'dan_installer_private_desktop_runner.exe'
    $process = Start-Process -FilePath $runner -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput ($log + '.runner.txt') -RedirectStandardError ($log + '.runner-error.txt')
    if (-not $process.WaitForExit(40000)) { throw "Private renderer did not finish; exact PID retained: $($process.Id)" }
    $process.Refresh()
    if ($process.ExitCode -ne 0) { throw "Expected fictional installation and ordinary Finish (0); got $($process.ExitCode): $log" }
    $text = [IO.File]::ReadAllText($log)
    if ($text -match 'QA UI (RENDER FAILED|CORNER MISMATCH|GEOMETRY FAILED|BRAND FAILED|BUTTON FONT FAILED)' -or $text -notmatch 'QA UI all six button corners match actual VCL parent' -or $text -notmatch 'QA UI real HWND centers, bounds and spacing pass') { throw "Rendering, font, corners or geometry evidence failed: $log" }
    $fontEvidence = Get-Content -LiteralPath (Join-Path $frames 'button-fonts.tsv')
    if ($fontEvidence.Count -ne 20 -or ($fontEvidence -match 'FAIL').Count -ne 0) { throw "Missing/failed actual bold font evidence: $log" }
    $hasLayoutFailure = $text -match 'QA UI (FOOTER CLIPPED|FINISHED ACTIONS MISPLACED)'
    if ($ExpectLayoutFailure -and -not $hasLayoutFailure) { throw 'Negative regression did not reproduce a layout failure.' }
    if (-not $ExpectLayoutFailure -and $hasLayoutFailure) { throw "Actual page layout/painter regression: $log" }
    foreach ($name in @('player','player-fade','directory','installing','finished')) {
        if (-not (Test-Path -LiteralPath (Join-Path $frames ($name + '.png')) -PathType Leaf)) { throw "Missing $theme/$name render" }
        if (-not $ExpectLayoutFailure -and $text -notmatch ('QA UI footer fully visible: ' + $name)) { throw "Missing $theme/$name paint-region evidence" }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $target 'Dan Player.exe')) -or $text -notmatch 'Verified installation committed') { throw 'Did not reach real installation completion.' }
    Write-Output "PASS actual Inno ${theme}/font${fontSize}: 5 real page renders; negative-layout=$([bool]$ExpectLayoutFailure); fictional sandbox installation only. $frames"
  }
}
Write-Output 'PASS production Inno wizard/dialog font baseline: 11 pt; QA metrics retain independent overrides.'
Write-Output "RESULT $($FontSizes.Count * 2) Inno theme/font-metric scenarios passed (OS DPI unchanged): $renderRoot"
