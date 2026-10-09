#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string] $NativeDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workspace = Split-Path -Parent $repository
. (Join-Path $repository 'scripts\support\bundled_fonts.ps1')
$font = Get-BundledInstallerFont -RepositoryRoot $repository
$qa = Join-Path $workspace ('tool\qa-local\qa-installer\installer-font-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$isolatedTemp = Join-Path $qa 'temp'
$null = New-Item -ItemType Directory -Path $isolatedTemp -Force
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
try {
    $env:TEMP = $isolatedTemp
    $env:TMP = $isolatedTemp
    $payload = Join-Path $qa 'fictional-payload'
    foreach ($relative in @('Dan Player.exe', 'data/app.so', 'native_assets.json', 'DESKTOP-LYRIC-MODE')) {
        $path = Join-Path $payload $relative
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force
        $text = if ($relative -eq 'DESKTOP-LYRIC-MODE') { "shared-executable-v1`n" } else { 'Fictional shared-font fixture; never executed.' }
        [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
    }
    $runtimeFont = Join-Path $payload $font.PayloadRelativePath
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $runtimeFont) -Force
    Copy-Item -LiteralPath $font.SourcePath -Destination $runtimeFont
    $output = @(& (Join-Path $repository 'scripts\build_windows_installer.ps1') -QaBuild -PayloadDirectory $payload -OutputRoot (Join-Path $qa 'packages') -NativeDirectory $NativeDirectory)
    $package = $output | Where-Object { $_.PSObject.Properties.Name -contains 'Installer' } | Select-Object -Last 1
    if (-not $package) { throw 'Missing fictional shared-font installer.' }
    $entries = [IO.File]::ReadAllText((Join-Path (Split-Path -Parent $package.Installer) 'payload-files.iss'))
    $sourceLiteral = 'Source: "' + $font.SourcePath + '";'
    if (@($entries -split '\r?\n' | Where-Object { $_.StartsWith($sourceLiteral, [StringComparison]::Ordinal) }).Count -ne 1) {
        throw 'Runtime font entry must use the authoritative wizard source exactly once.'
    }
    $target = Join-Path $qa 'fictional-install'
    $log = Join-Path $qa 'render.log'
    $runner = Join-Path $NativeDirectory 'dan_installer_private_desktop_runner.exe'
    $arguments = '"' + $package.Installer + '" "' + $target + '" "' + $log + '" render'
    $process = Start-Process -FilePath $runner -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput ($log + '.runner.txt') -RedirectStandardError ($log + '.runner-error.txt')
    if (-not $process.WaitForExit(40000)) { throw "Private font sandbox timed out; owned PID retained: $($process.Id)" }
    $process.Refresh()
    if ($process.ExitCode -ne 0) { throw "Private font installation failed: $log" }
    $installedFont = Join-Path $target $font.PayloadRelativePath
    if ((Get-Item -LiteralPath $installedFont).Length -ne $font.Bytes -or
        (Get-FileHash -LiteralPath $installedFont -Algorithm SHA256).Hash.ToLowerInvariant() -cne $font.Sha256) {
        throw 'Installed shared font differs from its pinned original.'
    }
    $text = [IO.File]::ReadAllText($log)
    if ($text -notmatch 'Verified installation committed' -or $text -match 'QA UI .*FAILED') { throw "Font sandbox did not finish its verified installation: $log" }
    $fontEvidence = @(Get-Content -LiteralPath (Join-Path $qa 'button-fonts.tsv'))
    if ($fontEvidence.Count -ne 20 -or @($fontEvidence -match 'FAIL').Count -ne 0) { throw 'Shared embedded font failed real HWND font checks.' }
    Write-Output "PASS: shared-source font extracted, rendered and installed with original SHA-256; sandbox=$qa"
} finally {
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
}
