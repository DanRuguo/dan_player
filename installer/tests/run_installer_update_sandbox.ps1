#requires -Version 5.1
[CmdletBinding()]
param([string] $NativeDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workspace = Split-Path -Parent $repository
if (-not $NativeDirectory) { $NativeDirectory = Join-Path $workspace 'tool\qa-installer\build\Release' }
$qaRoot = Join-Path $workspace ('tool\qa-installer\update-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$payload = Join-Path $qaRoot 'fictional-payload'
foreach ($relative in @('Dan Player.exe','data\app.so','desktop_lyric\desktop_lyric.exe','engine.dll','native_assets.json')) {
    $path = Join-Path $payload $relative
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force
    $text = if ($relative -eq 'Dan Player.exe') { 'fictional new player payload' } else { 'fictional new update file' }
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}
$outputs = @(& (Join-Path $repository 'scripts\build_windows_installer.ps1') -QaBuild -PayloadDirectory $payload -OutputRoot (Join-Path $qaRoot 'packages') -NativeDirectory $NativeDirectory)
$package = $outputs | Where-Object { $_.PSObject.Properties.Name -contains 'Installer' } | Select-Object -Last 1
if (-not $package) { throw 'No QA package was produced' }
& (Join-Path $NativeDirectory 'dan_installer_update_gate_test.exe') (Join-Path $qaRoot 'native-sandbox') 2>&1 | Tee-Object -FilePath (Join-Path $qaRoot 'native-update-gate.log')
if ($LASTEXITCODE -ne 0) { throw 'Native update gate failed' }
& (Join-Path $NativeDirectory 'dan_installer_inno_update_test.exe') $package.Installer (Join-Path $qaRoot 'cases') $package.Version 2>&1 | Tee-Object -FilePath (Join-Path $qaRoot 'inno-update.log')
if ($LASTEXITCODE -ne 0) { throw "Actual Inno update flow failed: $qaRoot" }
Write-Output "Update evidence: $qaRoot"
