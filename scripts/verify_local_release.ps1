param(
    [Parameter(Mandatory=$true)][string] $ReceiptPath,
    [switch] $UnsignedCandidate,
    [string] $SigningThumbprint = $env:RCEIT_SIGNING_THUMBPRINT
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$expectedSigningThumbprint = ($SigningThumbprint -replace '\s', '').ToUpperInvariant()
if (-not $expectedSigningThumbprint) {
    # Preserve verification of historical releases when no certificate is selected.
    $expectedSigningThumbprint = 'E11D145A3C0D7298F4D3E96BADC497E360CAF510'
}
if ($expectedSigningThumbprint -notmatch '^[0-9A-F]{40}$') {
    throw 'SigningThumbprint must contain exactly 40 hexadecimal characters (whitespace is ignored).'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-ReleaseDesktopLyricMode([string] $Payload, $Receipt) {
    $modePath = Join-Path $Payload 'DESKTOP-LYRIC-MODE'
    $shared = Test-Path -LiteralPath $modePath
    $mode = 'separate-helper-v1'
    if ($shared) {
        if (-not (Test-Path -LiteralPath $modePath -PathType Leaf) -or
            [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($modePath)) -cne "shared-executable-v1`n") {
            throw 'Invalid DESKTOP-LYRIC-MODE marker; expected exact ASCII shared-executable-v1 followed by LF.'
        }
        $mode = 'shared-executable-v1'
        if ((Test-Path -LiteralPath (Join-Path $Payload 'desktop_lyric')) -or
            (Test-Path -LiteralPath (Join-Path $Payload 'desktop_lyric.exe'))) {
            throw 'Mixed executable layouts: shared release contains a legacy desktop lyrics helper.'
        }
    } elseif (-not (Test-Path -LiteralPath (Join-Path $Payload 'desktop_lyric\desktop_lyric.exe') -PathType Leaf)) {
        throw 'Legacy release without DESKTOP-LYRIC-MODE requires desktop_lyric\desktop_lyric.exe.'
    }
    if (($Receipt.PSObject.Properties.Name -contains 'DesktopLyricMode') -and $Receipt.DesktopLyricMode -cne $mode) {
        throw 'Release receipt and desktop lyrics layout disagree.'
    }
    $provenance = Get-Content -LiteralPath (Join-Path $Payload 'BUILD-PROVENANCE.json') -Raw | ConvertFrom-Json
    if ($shared -or ($provenance.PSObject.Properties.Name -contains 'DesktopLyricMode')) {
        if (-not ($provenance.PSObject.Properties.Name -contains 'DesktopLyricMode') -or $provenance.DesktopLyricMode -cne $mode) {
            throw 'Build provenance and desktop lyrics layout disagree.'
        }
    }
    if ($shared) {
        if (-not ($Receipt.PSObject.Properties.Name -contains 'DesktopLyricMode') -or
            -not ($Receipt.PSObject.Properties.Name -contains 'DisplayVersion') -or
            -not ($provenance.PSObject.Properties.Name -contains 'DisplayVersion') -or
            $Receipt.DisplayVersion -cne $Receipt.Version -or
            $provenance.DisplayVersion -cne $Receipt.DisplayVersion -or
            $provenance.Version -cne $Receipt.Version) {
            throw 'Shared-executable release is missing matching layout/display-version receipts.'
        }
    }
    $reports = @('FONT-INTEGRITY.json')
    if (-not $shared) { $reports += 'desktop_lyric/FONT-INTEGRITY.json' }
    if (@($provenance.FontIntegrityReports).Count -ne $reports.Count -or
        @($reports | Where-Object { $_ -notin $provenance.FontIntegrityReports }).Count -ne 0) {
        throw 'Font audit reports do not match the executable layout.'
    }
    return $mode
}

$receipt = Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json
$repo = Split-Path -Parent $PSScriptRoot
$workspace = Split-Path -Parent $repo
$payload = [IO.Path]::GetFullPath($receipt.PackageDirectory)
$zipPath = [IO.Path]::GetFullPath($receipt.ZipPath)
foreach ($target in @($payload, $zipPath)) {
    if (-not $target.StartsWith($workspace + '\dist\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Release receipt escaped the workspace dist directory.'
    }
}
if ((Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $receipt.ZipSha256) {
    throw 'Archive checksum does not match the assembly receipt.'
}
$desktopLyricMode = Get-ReleaseDesktopLyricMode $payload $receipt
$sharedExecutable = $desktopLyricMode -eq 'shared-executable-v1'
$requiredEntries = @('Dan Player.exe', 'rust_lib_dan_player.dll', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/FontManifest.json', 'FONT-INTEGRITY.json', 'BUILD-PROVENANCE.json')
$ownedBinaries = @('Dan Player.exe', 'rust_lib_dan_player.dll')
if ($sharedExecutable) {
    . (Join-Path $PSScriptRoot 'support\release_version.ps1')
    $sourceVersion = Get-ReleaseVersionInfo $repo
    if ($sourceVersion.DisplayVersion -cne $receipt.DisplayVersion) { throw 'Packaged display version does not match the final source.' }
    $requiredEntries += 'DESKTOP-LYRIC-MODE'
} else {
    $requiredEntries += @('desktop_lyric/desktop_lyric.exe', 'desktop_lyric/flutter_windows.dll', 'desktop_lyric/data/app.so', 'desktop_lyric/data/icudtl.dat', 'desktop_lyric/data/flutter_assets/FontManifest.json', 'desktop_lyric/FONT-INTEGRITY.json')
    $ownedBinaries += 'desktop_lyric\desktop_lyric.exe'
}
$sourcePairs = @{
    'Dan Player.exe' = 'build\windows\x64\runner\Release\Dan Player.exe'
    'rust_lib_dan_player.dll' = 'build\windows\x64\runner\Release\rust_lib_dan_player.dll'
    'data\app.so' = 'build\windows\x64\runner\Release\data\app.so'

}
if (-not $sharedExecutable) {
    $sourcePairs['desktop_lyric\desktop_lyric.exe'] = 'third_party\desktop_lyric\build\windows\x64\runner\Release\desktop_lyric.exe'
    $sourcePairs['desktop_lyric\data\app.so'] = 'third_party\desktop_lyric\build\windows\x64\runner\Release\data\app.so'
}
foreach ($relative in $sourcePairs.Keys) {
    if ((Get-FileHash -LiteralPath (Join-Path $payload $relative) -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $repo $sourcePairs[$relative]) -Algorithm SHA256).Hash) {
        throw "Payload does not match final source/build: $relative"
    }
}
$bassFx = & (Join-Path $PSScriptRoot 'prepare_bass_fx_runtime.ps1') -Offline -VerifyOnly
foreach ($pair in @(
    @{ Relative = 'BASS\bass_fx.dll'; Hash = $bassFx.Package.DllSha256 },
    @{ Relative = 'licenses\BASS_FX\bass_fx.txt'; Hash = $bassFx.Package.NoticeSha256 },
    @{ Relative = 'licenses\BASS_FX\bass_fx24-2.4.12.6.zip'; Hash = $bassFx.Package.ArchiveSha256 }
)) {
    if ((Get-FileHash -LiteralPath (Join-Path $payload $pair.Relative) -Algorithm SHA256).Hash -ne $pair.Hash) {
        throw "BASS_FX payload is not the pinned original: $($pair.Relative)"
    }
}
$prefix = [IO.Path]::GetFileName($payload) + '/'
$checksums = Get-Content -LiteralPath (Join-Path $payload 'SHA256SUMS')
$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
$checked = 0
$checkedNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
try {
    foreach ($line in $checksums) {
        if (-not $line) { continue }
        if ($line -notmatch '^([a-f0-9]{64})  (.+)$') { throw 'Malformed payload checksum line.' }
        $expected = $Matches[1]
        $name = $Matches[2]
        if (-not $checkedNames.Add($name)) { throw "Duplicate payload checksum entry: $name" }
        if ($name.Contains('..') -or $name.StartsWith('/') -or $name.Contains(':') -or $name.EndsWith('.pfx')) {
            throw "Unsafe/private payload path: $name"
        }
        $payloadHash = (Get-FileHash -LiteralPath (Join-Path $payload $name) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($payloadHash -ne $expected) { throw "Staged payload checksum mismatch: $name" }
        $entry = $zip.GetEntry($prefix + $name)
        if ($null -eq $entry) { throw "Missing archive entry: $name" }
        $stream = $entry.Open()
        $hasher = [Security.Cryptography.SHA256]::Create()
        try {
            $actual = [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
            if ($actual -ne $expected) { throw "Archive payload checksum mismatch: $name" }
        } finally {
            $hasher.Dispose()
            $stream.Dispose()
        }
        $checked++
    }
    foreach ($requiredEntry in $requiredEntries) {
        if (-not $checkedNames.Contains($requiredEntry) -or -not $zip.GetEntry($prefix + $requiredEntry)) {
            throw "Missing required hashed release entry: $requiredEntry"
        }
    }
    if ($sharedExecutable -and @($zip.Entries | Where-Object {
        $_.FullName.StartsWith($prefix + 'desktop_lyric/', [StringComparison]::OrdinalIgnoreCase) -or
        $_.FullName.Equals($prefix + 'desktop_lyric.exe', [StringComparison]::OrdinalIgnoreCase)
    }).Count -gt 0) { throw 'Shared-executable archive contains a legacy desktop lyrics helper.' }
    $fileEntries = @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
    if ($fileEntries.Count -ne $checked + 1) { throw 'Archive contains an unexpected/duplicate entry.' }
    $manifestEntry = $zip.GetEntry($prefix + 'SHA256SUMS')
    if ($null -eq $manifestEntry) { throw 'Archive payload manifest is missing.' }
    $manifestStream = $manifestEntry.Open()
    $manifestHasher = [Security.Cryptography.SHA256]::Create()
    try {
        $manifestHash = [BitConverter]::ToString($manifestHasher.ComputeHash($manifestStream)).Replace('-', '').ToLowerInvariant()
        $stagedManifestHash = (Get-FileHash -LiteralPath (Join-Path $payload 'SHA256SUMS') -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($manifestHash -ne $stagedManifestHash) { throw 'Archive manifest differs from the staged manifest.' }
    } finally {
        $manifestHasher.Dispose()
        $manifestStream.Dispose()
    }
} finally { $zip.Dispose() }
$signatures = foreach ($relative in $ownedBinaries) {
    $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $payload $relative)
    if ($UnsignedCandidate) {
        if ($signature.Status.ToString() -ne 'NotSigned' -or $null -ne $signature.SignerCertificate) {
            throw "Local unsigned candidate contains a signed/stale/invalid own binary: $relative"
        }
        [pscustomobject]@{ File = $relative; Status = 'NotSigned'; Subject = $null; Thumbprint = $null }
        continue
    }
    if ($null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Thumbprint -ne $expectedSigningThumbprint -or
        $signature.Status.ToString() -in @('NotSigned', 'HashMismatch', 'NotSupported')) {
        throw "Signature missing, changed, or invalid: $relative"
    }
    [pscustomobject]@{
        File = $relative
        Subject = $signature.SignerCertificate.Subject
        Thumbprint = $signature.SignerCertificate.Thumbprint
        Expires = $signature.SignerCertificate.NotAfter.ToString('o')
        Status = $signature.Status.ToString()
        StatusMessage = $signature.StatusMessage
    }
}
[pscustomobject]@{
    Passed = $true
    Version = $receipt.Version
    DesktopLyricMode = $desktopLyricMode
    UnsignedCandidate = [bool]$UnsignedCandidate
    ZipPath = $zipPath
    ZipBytes = (Get-Item -LiteralPath $zipPath).Length
    ZipSha256 = $receipt.ZipSha256
    CheckedPayloadEntries = $checked
    SourceAndBuildMatches = $sourcePairs.Count
    Signatures = @($signatures)
}
