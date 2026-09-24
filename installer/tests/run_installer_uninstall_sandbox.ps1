#requires -Version 5.1
<#
Runs one real Inno install/uninstall against fictional bytes under the workspace.
The QA AppId has no uninstall registry key and redirects both shortcuts locally.
Never pass this script a production installer or a real application directory.
#>
[CmdletBinding()]
param([string] $NativeDirectory, [string] $Compiler)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workspace = Split-Path -Parent $repository
$qaParent = [IO.Path]::GetFullPath((Join-Path $workspace 'tool/qa-installer'))
$qaRoot = Join-Path $qaParent ('installer-uninstall-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $qaRoot
$qaPrefix = $qaRoot.TrimEnd('\', '/') + '\'
function Assert-QaPath([string] $Value) {
    $full = [IO.Path]::GetFullPath($Value)
    if (-not $full.StartsWith($qaPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "QA path escapes the isolated case directory: $full"
    }
    return $full
}
function Write-Fixture([string] $Relative, [string] $Text) {
    $file = Assert-QaPath (Join-Path $payload $Relative)
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force
    [IO.File]::WriteAllText($file, $Text, [Text.UTF8Encoding]::new($false))
}
function Assert-True([bool] $Value, [string] $Message) {
    if (-not $Value) { throw $Message }
}
function Invoke-QaProcess([string] $Executable, [string] $Arguments, [string] $Name) {
    $process = Start-Process -FilePath $Executable -ArgumentList $Arguments -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(60000)) {
        throw "$Name exceeded 60 seconds; only the owned QA PID $($process.Id) was started"
    }
    $process.Refresh()
    Assert-True ($process.ExitCode -eq 0) "$Name failed with exit code $($process.ExitCode)"
}

if (-not $NativeDirectory) {
    $NativeDirectory = Join-Path $workspace 'tool/qa-installer/2605-sep14/Release'
}
$payload = Assert-QaPath (Join-Path $qaRoot 'fictional-payload')
Write-Fixture 'Dan Player.exe' 'FICTIONAL FIXTURE. Not an executable.'
Write-Fixture 'data/app.so' 'FICTIONAL FIXTURE. Not AOT.'
Write-Fixture 'desktop_lyric/desktop_lyric.exe' 'FICTIONAL FIXTURE. Not an executable.'
Write-Fixture 'engine.dll' 'FICTIONAL FIXTURE. Not a DLL.'
Write-Fixture 'native_assets.json' '{"fixture":"uninstall-sandbox"}'

$buildArguments = @{
    QaBuild = $true
    PayloadDirectory = $payload
    OutputRoot = (Assert-QaPath (Join-Path $qaRoot 'packages'))
    NativeDirectory = $NativeDirectory
}
if ($Compiler) { $buildArguments.Compiler = $Compiler }
$output = @(& (Join-Path $repository 'scripts/build_windows_installer.ps1') @buildArguments)
$package = $output | Where-Object { $_.PSObject.Properties.Name -contains 'Installer' } | Select-Object -Last 1
if (-not $package -or -not $package.QaBuild -or $package.Signed -or
    -not $package.Installer.EndsWith('-QA.exe', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Only the unsigned fictional QA Setup is allowed'
}
$setup = Assert-QaPath $package.Installer
$target = Assert-QaPath (Join-Path $qaRoot 'case/install')
$installLog = Assert-QaPath (Join-Path $qaRoot 'case/install.log')
$uninstallLog = Assert-QaPath (Join-Path $qaRoot 'case/uninstall.log')
$desktopLink = Assert-QaPath (Join-Path $qaRoot 'case/redirect-desktop/Dan Player.lnk')
$startLink = Assert-QaPath (Join-Path $qaRoot 'case/redirect-start/Dan Player.lnk')
$uninstaller = Assert-QaPath (Join-Path $target '.dan-player-install/unins000.exe')
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
$oldTemp = $env:TEMP
$oldTmp = $env:TMP
$isolatedTemp = Assert-QaPath (Join-Path $qaRoot 'temp')
$null = New-Item -ItemType Directory -Path $isolatedTemp
try {
    $env:TEMP = $isolatedTemp
    $env:TMP = $isolatedTemp
    $installArgs = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="' + $target +
        '" /LOG="' + $installLog + '" /QADESKTOP=1 /QASTART=1'
    Invoke-QaProcess $setup $installArgs 'Fictional QA installation'
    Assert-True (Test-Path -LiteralPath $uninstaller -PathType Leaf) 'QA uninstaller missing'
    Assert-True (Test-Path -LiteralPath $desktopLink -PathType Leaf) 'Redirected desktop link missing'
    Assert-True (Test-Path -LiteralPath $startLink -PathType Leaf) 'Redirected start link missing'

    $unknown = Assert-QaPath (Join-Path $target 'my-music-and-notes.txt')
    [IO.File]::WriteAllText($unknown, 'Unmanaged user file must survive.', [Text.UTF8Encoding]::new($false))
    $externalData = Assert-QaPath (Join-Path $qaRoot 'case/user-data/settings.json')
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $externalData) -Force
    [IO.File]::WriteAllText($externalData, '{"preserve":true}', [Text.UTF8Encoding]::new($false))

    $uninstallArgs = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG="' + $uninstallLog + '"'
    Invoke-QaProcess $uninstaller $uninstallArgs 'Fictional QA uninstallation'
    foreach ($relative in @('Dan Player.exe', 'data/app.so', 'desktop_lyric/desktop_lyric.exe',
            'engine.dll', 'native_assets.json', '.dan-player-install/payload.manifest')) {
        Assert-True -Value (-not (Test-Path -LiteralPath (Assert-QaPath (Join-Path $target $relative)))) -Message "Inno left a managed file behind: $relative"
    }
    Assert-True (-not (Test-Path -LiteralPath $desktopLink)) 'Inno left the redirected desktop shortcut'
    Assert-True (-not (Test-Path -LiteralPath $startLink)) 'Inno left the redirected Start shortcut'
    Assert-True -Value (([IO.File]::ReadAllText($unknown)) -ceq 'Unmanaged user file must survive.') -Message 'Inno deleted or changed an unknown file in the install directory'
    Assert-True -Value (([IO.File]::ReadAllText($externalData)) -ceq '{"preserve":true}') -Message 'Inno deleted or changed external user data'
    Write-Output "PASS fictional QA install/uninstall: managed files and redirected shortcuts removed; unknown file and separate user data preserved. Logs: $qaRoot"
} finally {
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
}
