[CmdletBinding()]
param(
    [switch] $SkipDesktopLyric,
    [switch] $SkipSigning,
    [switch] $SkipPackaging,
    [switch] $NoRestore,
    [switch] $OfflineRuntime,
    [string] $OutputRoot,
    [string] $CertificateThumbprint = $env:RCEIT_SIGNING_THUMBPRINT,
    [string] $TimestampServer,
    [ValidateSet('Development', 'Integration', 'Release')] [string] $ValidationScope = 'Release',
    [string[]] $TestFile,
    [switch] $NoReuse
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repositoryRoot
. (Join-Path $PSScriptRoot 'support\release_version.ps1')
. (Join-Path $PSScriptRoot 'support\validation_receipt.ps1')
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
        & (Join-Path $PSScriptRoot 'verify_interaction_regressions.ps1') -ProjectRoot $repositoryRoot -Flutter $flutter -Scope $ValidationScope -TestFile $TestFile -NoReuse:$NoReuse
        if ($ValidationScope -eq 'Development') {
            Write-Host 'Development coverage complete. No release build, signing or packaging was requested by this scope.'
            return
        }
        $buildInputs = Get-ValidationInputs $repositoryRoot -BuildOnly
        $buildTools = Get-ValidationToolchain $flutter -Native
        $mainRelease = Join-Path $repositoryRoot 'build/windows/x64/runner/Release'
        $buildReceiptPath = Join-Path $workspaceRoot 'tool/validation/windows-build.json'
        $buildReceipt = Read-LocalValidationReceipt $buildReceiptPath
        $records = @(Get-ArtifactContentRecords $mainRelease)
        if (-not $NoReuse -and (Test-ArtifactReceipt $buildReceipt $buildInputs $buildTools $records)) {
            Write-Host "Reusing complete Windows payload verified by SHA-256: $($buildInputs.Hash)"
        } else {
            & (Join-Path $PSScriptRoot 'invalidate_windows_icon_assets.ps1') -ProjectRoot $repositoryRoot
            & $flutter build windows --release --no-pub
            if ($LASTEXITCODE -ne 0) { throw 'Dan Player release build failed.' }
        }
        & (Join-Path $PSScriptRoot 'verify_windows_release_fonts.ps1') -ProjectRoot $repositoryRoot
    } finally {
        Pop-Location
    }

    if ($SkipDesktopLyric) {
        Write-Host 'SkipDesktopLyric is retained for compatibility. Desktop lyrics share the main executable and are always included.'
    }

    if (-not $SkipSigning -and $ValidationScope -eq 'Release') {
        $signingParameters = @{}
        if ($CertificateThumbprint) {
            $signingParameters.Thumbprint = $CertificateThumbprint
        }
        if ($TimestampServer) {
            $signingParameters.TimestampServer = $TimestampServer
        }
        & (Join-Path $PSScriptRoot 'sign_windows_release.ps1') @signingParameters
    }

    if ((Get-ValidationInputs $repositoryRoot -BuildOnly).Hash -cne $buildInputs.Hash) { throw 'Source changed during build/signing; refusing to package mismatched inputs.' }
    $records = @(Get-ArtifactContentRecords $mainRelease)
    if ($records.Count -eq 0) { throw 'The release payload is empty.' }
    Write-LocalValidationReceipt $buildReceiptPath ([ordered]@{
        Schema=1; Passed=$true; Tests=@(); Scope='WindowsReleasePayload'; Inputs=$buildInputs; Toolchain=$buildTools;
        ArtifactHash=(Get-TextSha256 ($records | ConvertTo-Json -Compress)); Artifacts=$records;
        CompletedAt=[DateTime]::UtcNow.ToString('o')
    })

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
