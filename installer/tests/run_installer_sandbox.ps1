#requires -Version 5.1
[CmdletBinding()]
param([string] $NativeDirectory, [string] $Compiler)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$testRepository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$testWorkspace = Split-Path -Parent $testRepository
if (-not $NativeDirectory) { $NativeDirectory = Join-Path $testWorkspace 'tool\qa-installer\build\Release' }
$testRoot = Join-Path $testWorkspace ('tool\qa-installer\inno-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$null = New-Item -ItemType Directory -Path $testRoot
function Write-Fixture([string] $Path, [string] $Text) {
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
$payload = Join-Path $testRoot 'synthetic-payload'
Write-Fixture (Join-Path $payload 'Dan Player.exe') 'FICTIONAL FIXTURE. Not an executable. New version.'
Write-Fixture (Join-Path $payload 'data\app.so') 'FICTIONAL FIXTURE. Not AOT.'
Write-Fixture (Join-Path $payload 'desktop_lyric\desktop_lyric.exe') 'FICTIONAL FIXTURE. Not an executable.'
Write-Fixture (Join-Path $payload 'engine.dll') 'FICTIONAL FIXTURE. Not a DLL.'
Write-Fixture (Join-Path $payload 'native_assets.json') '{"fixture":"synthetic native asset manifest"}'
$buildArguments = @{ PayloadDirectory=$payload; OutputRoot=(Join-Path $testRoot 'packages'); QaBuild=$true }
if ($NativeDirectory) { $buildArguments.NativeDirectory = $NativeDirectory }
if ($Compiler) { $buildArguments.Compiler = $Compiler }
$output = @(& (Join-Path $testRepository 'scripts\build_windows_installer.ps1') @buildArguments)
$package = $output | Where-Object { $_.PSObject.Properties.Name -contains 'Installer' } | Select-Object -Last 1
if (-not $package -or -not (Test-Path -LiteralPath $package.Installer)) { throw 'QA package was not built' }

function Invoke-QaInstaller([string] $Target, [string] $Name, [int] $FailAfter=0,
    [int] $Desktop=1, [int] $StartMenu=1, [int] $FailAfterReady=0, [int] $CancelAfter=0) {
    $log = Join-Path $testRoot ($Name + '.log')
    $arguments = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="' + $Target + '" /LOG="' + $log + '" /QAFAILAFTER=' + $FailAfter
    $arguments += " /QADESKTOP=$Desktop /QASTART=$StartMenu /QAFAILAFTERREADY=$FailAfterReady /QACANCELAFTER=$CancelAfter"
    if ($CancelAfter -gt 0) {
        $runner = Join-Path $NativeDirectory 'dan_installer_private_desktop_runner.exe'
        $privateArguments = '"' + $package.Installer + '" "' + $Target + '" "' + $log + '" ' + $CancelAfter
        $process = Start-Process -FilePath $runner -ArgumentList $privateArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput ($log + '.runner.txt') -RedirectStandardError ($log + '.runner-error.txt')
    } else {
        $process = Start-Process -FilePath $package.Installer -ArgumentList $arguments -WindowStyle Hidden -PassThru
    }
    if (-not $process.WaitForExit(60000)) { throw "QA installer exceeded 60 seconds; process left intact. PID=$($process.Id)" }
    $process.Refresh()
    return [pscustomobject]@{ ExitCode=$process.ExitCode; Log=$log }
}
function Assert-Text([string] $Path, [string] $Expected) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or [IO.File]::ReadAllText($Path) -ne $Expected) { throw "Fixture bytes differ: $Path" }
}
function Assert-True([bool] $Value, [string] $Message) { if (-not $Value) { throw $Message } }

$fresh = Join-Path $testRoot 'new-install\install'
$installed = Invoke-QaInstaller $fresh 'new-install'
Assert-True ($installed.ExitCode -eq 0) "New installation failed: $($installed.Log)"
Assert-Text (Join-Path $fresh 'Dan Player.exe') 'FICTIONAL FIXTURE. Not an executable. New version.'
Assert-Text (Join-Path $fresh 'native_assets.json') '{"fixture":"synthetic native asset manifest"}'
Assert-True (Test-Path -LiteralPath (Join-Path $testRoot 'new-install\redirect-desktop\Dan Player.lnk')) 'Redirected desktop shortcut missing'
Assert-True (Test-Path -LiteralPath (Join-Path $testRoot 'new-install\redirect-start\Dan Player.lnk')) 'Redirected start shortcut missing'
Assert-True (Test-Path -LiteralPath (Join-Path $fresh '.dan-player-install\unins000.exe')) 'QA must exercise actual uninstall metadata without registering it'
Write-Output 'PASS Inno new install with redirected shortcuts'

foreach ($desktop in @(0,1)) {
    foreach ($start in @(0,1)) {
        if ($desktop -eq 1 -and $start -eq 1) { continue }
        $scenario = "shortcuts-$desktop-$start"
        $target = Join-Path $testRoot ($scenario + '\install')
        $result = Invoke-QaInstaller $target $scenario 0 $desktop $start
        Assert-True ($result.ExitCode -eq 0) "Shortcut combination failed: $($result.Log)"
        $desktopExists = Test-Path -LiteralPath (Join-Path $testRoot ($scenario + '\redirect-desktop\Dan Player.lnk'))
        $startExists = Test-Path -LiteralPath (Join-Path $testRoot ($scenario + '\redirect-start\Dan Player.lnk'))
        Assert-True ($desktopExists -eq [bool]$desktop) "Desktop selection ignored: $scenario"
        Assert-True ($startExists -eq [bool]$start) "Start selection ignored: $scenario"
        Write-Output "PASS Inno desktop/start combination $desktop/$start"
    }
}

$unicode = Join-Path $testRoot '自选父目录\我的播放器 最终路径'
$installed = Invoke-QaInstaller $unicode 'unicode-manual'
Assert-True ($installed.ExitCode -eq 0) "Unicode manual path failed: $($installed.Log)"
Assert-Text (Join-Path $unicode 'Dan Player.exe') 'FICTIONAL FIXTURE. Not an executable. New version.'
Write-Output 'PASS Inno exact Unicode final path'

Write-Fixture (Join-Path $fresh 'user-notes.txt') 'Unrelated original file, never remove.'
$originalHash = (Get-FileHash -LiteralPath (Join-Path $fresh 'Dan Player.exe') -Algorithm SHA256).Hash
$desktopHash = (Get-FileHash -LiteralPath (Join-Path $testRoot 'new-install\redirect-desktop\Dan Player.lnk') -Algorithm SHA256).Hash
$uninstallHash = (Get-FileHash -LiteralPath (Join-Path $fresh '.dan-player-install\unins000.dat') -Algorithm SHA256).Hash
$failed = Invoke-QaInstaller $fresh 'injected-copy-failure' 2
Assert-True ($failed.ExitCode -ne 0) 'Injected failure was reported as success'
Assert-True ((Get-FileHash -LiteralPath (Join-Path $fresh 'Dan Player.exe') -Algorithm SHA256).Hash -eq $originalHash) 'Original EXE bytes not restored after Inno failure'
Assert-True ((Get-FileHash -LiteralPath (Join-Path $testRoot 'new-install\redirect-desktop\Dan Player.lnk') -Algorithm SHA256).Hash -eq $desktopHash) 'Original shortcut bytes not restored'
Assert-Text (Join-Path $fresh 'user-notes.txt') 'Unrelated original file, never remove.'
Write-Output 'PASS Inno injected failure restores previous installation and preserves unknown file'

$failed = Invoke-QaInstaller $fresh 'injected-late-failure' 0 1 1 1
Assert-True ($failed.ExitCode -ne 0) 'Late verification failure was reported as success'
Assert-True ((Get-FileHash -LiteralPath (Join-Path $fresh 'Dan Player.exe') -Algorithm SHA256).Hash -eq $originalHash) 'Late failure did not restore original exe'
Assert-True ((Get-FileHash -LiteralPath (Join-Path $fresh '.dan-player-install\unins000.dat') -Algorithm SHA256).Hash -eq $uninstallHash) 'Late failure did not restore original uninstall metadata'
Write-Output 'PASS Inno late failure preserves recovery through final success boundary'

$cancelled = Invoke-QaInstaller $fresh 'user-cancelled' 0 1 1 0 2
Assert-True ($cancelled.ExitCode -eq 5) 'Ordinary cancellation did not take the engine cancellation exit path'
$cancelLog = Get-Content -LiteralPath $cancelled.Log -Raw
Assert-True ($cancelLog -match '(?i)user cancel(?:l)?ed') 'No native user-cancelled event in Inno log'
Assert-True ($cancelLog -match '(?i)rolling back') 'No native Inno rollback in cancellation log'
Assert-True ($cancelLog -notmatch 'Verified installation committed') 'Cancelled install committed'
Assert-True ((Get-FileHash -LiteralPath (Join-Path $fresh 'Dan Player.exe') -Algorithm SHA256).Hash -eq $originalHash) 'User cancellation did not restore original executable'
Assert-True ((Get-FileHash -LiteralPath (Join-Path $fresh '.dan-player-install\unins000.dat') -Algorithm SHA256).Hash -eq $uninstallHash) 'User cancellation did not restore original uninstall metadata'
Write-Output 'PASS real Inno user cancellation and engine rollback restore the original installation'

$freshFailed = Join-Path $testRoot 'new-failure\install'
$failed = Invoke-QaInstaller $freshFailed 'new-failure' 2 0 0
Assert-True ($failed.ExitCode -ne 0) 'New installation failure was reported as success'
Assert-True (-not (Test-Path -LiteralPath $freshFailed)) 'New installation failure left managed files behind'
Write-Output 'PASS Inno new install cancellation restores empty destination'

$unrelated = Join-Path $testRoot 'unknown-app\install'
Write-Fixture (Join-Path $unrelated 'Dan Player.exe') 'Not a recognized Dan Player installation.'
$blocked = Invoke-QaInstaller $unrelated 'unknown-app'
Assert-True ($blocked.ExitCode -ne 0) 'Unrecognized existing EXE was overwritten'
Assert-Text (Join-Path $unrelated 'Dan Player.exe') 'Not a recognized Dan Player installation.'
Write-Output 'PASS Inno rejects unrecognized existing executable'

$concurrent = Join-Path $testRoot 'concurrent\install'
$firstLog = Join-Path $testRoot 'concurrent-first.log'
$firstArgs = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /QAHOLDAFTERBEGIN=1 /QADESKTOP=0 /QASTART=0 /DIR="' + $concurrent + '" /LOG="' + $firstLog + '"'
$first = Start-Process -FilePath $package.Installer -ArgumentList $firstArgs -WindowStyle Hidden -PassThru
$state = Join-Path $testRoot 'concurrent\.install.danplayer-recovery\state'
$prepared = $false
$deadline = [DateTime]::UtcNow.AddSeconds(15)
while ([DateTime]::UtcNow -lt $deadline -and -not $first.HasExited) {
    if ((Test-Path -LiteralPath $state) -and [IO.File]::ReadAllText($state) -eq 'prepared') { $prepared=$true; break }
    Start-Sleep -Milliseconds 100
    $first.Refresh()
}
Assert-True $prepared 'First installer did not reach its held prepared transaction'
$journal = Join-Path $testRoot 'concurrent\.install.danplayer-recovery\journal'
$journalHash = (Get-FileHash -LiteralPath $journal -Algorithm SHA256).Hash
$second = Invoke-QaInstaller $concurrent 'concurrent-second' 0 0 0
Assert-True ($second.ExitCode -ne 0) 'A second live Setup took over the active destination'
Assert-True ((Get-FileHash -LiteralPath $journal -Algorithm SHA256).Hash -eq $journalHash) 'Second Setup modified the active journal'
if (-not $first.WaitForExit(30000)) { throw 'First installer timeout; process left intact' }
$first.Refresh()
Assert-True ($first.ExitCode -eq 0) 'Second Setup disrupted the first installation'
Assert-True ([IO.File]::ReadAllText($state) -eq 'committed') 'First transaction did not commit normally'
Write-Output 'PASS concurrent second Setup refuses the live transaction without modifying its journal'
Write-Output ('RESULT 11 Inno sandbox scenarios passed. Logs: ' + $testRoot)
