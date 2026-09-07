[CmdletBinding()]
param(
    [switch] $SkipDesktopLyric,
    [switch] $SkipSigning,
    [switch] $SkipPackaging,
    [switch] $NoRestore,
    [switch] $OfflineRuntime,
    [string] $OutputRoot,
    [string] $CertificateThumbprint = $env:RCEIT_SIGNING_THUMBPRINT,
    [string] $TimestampServer
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repositoryRoot
. (Join-Path $PSScriptRoot 'support\release_version.ps1')
$null = Get-ReleaseVersionInfo $repositoryRoot
$flutter = Join-Path $workspaceRoot 'tool\flutter\bin\flutter.bat'
$pubCache = Join-Path $workspaceRoot 'tool\pub-cache'
$rustupHome = Join-Path $workspaceRoot 'tool\rustup'
$cargoHome = Join-Path $workspaceRoot 'tool\cargo'

if (-not (Test-Path -LiteralPath $flutter -PathType Leaf)) {
    throw "Flutter was not found at $flutter"
}

$previousPubCache = $env:PUB_CACHE
$previousRustupHome = $env:RUSTUP_HOME
$previousCargoHome = $env:CARGO_HOME
$previousFlutterRoot = $env:FLUTTER_ROOT
$previousPath = $env:Path
$env:PUB_CACHE = $pubCache
$env:RUSTUP_HOME = $rustupHome
$env:CARGO_HOME = $cargoHome
$env:FLUTTER_ROOT = Join-Path $workspaceRoot 'tool\flutter'
$env:Path = "$(Join-Path $cargoHome 'bin');$($env:Path)"
try {
    Push-Location $repositoryRoot
    try {
        if (-not $NoRestore) {
            & (Join-Path $PSScriptRoot 'prepare_windows_dependencies.ps1') -ProjectRoot $repositoryRoot -Flutter $flutter
        }
        & (Join-Path $PSScriptRoot 'verify_interaction_regressions.ps1') -ProjectRoot $repositoryRoot -Flutter $flutter
        & (Join-Path $PSScriptRoot 'invalidate_windows_icon_assets.ps1') -ProjectRoot $repositoryRoot
        & $flutter build windows --release --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Dan Player release build failed.' }
        & (Join-Path $PSScriptRoot 'verify_windows_release_fonts.ps1') -ProjectRoot $repositoryRoot
    } finally {
        Pop-Location
    }

    if ($SkipDesktopLyric) {
        Write-Host 'SkipDesktopLyric is retained for compatibility. Desktop lyrics share the main executable and are always included.'
    }

    if (-not $SkipSigning) {
        $signingParameters = @{}
        if ($CertificateThumbprint) {
            $signingParameters.Thumbprint = $CertificateThumbprint
        }
        if ($TimestampServer) {
            $signingParameters.TimestampServer = $TimestampServer
        }
        & (Join-Path $PSScriptRoot 'sign_windows_release.ps1') @signingParameters
    }

    if (-not $SkipPackaging) {
        $runtimeParameters = @{}
        if ($OfflineRuntime) { $runtimeParameters.Offline = $true }
        $runtime = & (Join-Path $PSScriptRoot 'prepare_bass_runtime.ps1') @runtimeParameters
        Write-Host "Verified BASS runtime: $($runtime.RuntimeDirectory)"
        $tempoRuntime = & (Join-Path $PSScriptRoot 'prepare_bass_fx_runtime.ps1') @runtimeParameters
        Write-Host "Verified BASS_FX tempo runtime: $($tempoRuntime.RuntimeDirectory)"
        $packageParameters = @{}
        if ($OutputRoot) { $packageParameters.OutputRoot = $OutputRoot }
        & (Join-Path $PSScriptRoot 'assemble_windows_release.ps1') @packageParameters
    }
} finally {
    $env:PUB_CACHE = $previousPubCache
    $env:RUSTUP_HOME = $previousRustupHome
    $env:CARGO_HOME = $previousCargoHome
    $env:FLUTTER_ROOT = $previousFlutterRoot
    $env:Path = $previousPath
}
