param(
    [Parameter(Mandatory=$true)][string] $ReceiptPath,
    [switch] $UnsignedCandidate
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem
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
$sourcePairs = @{
    'Dan Player.exe' = 'build\windows\x64\runner\Release\Dan Player.exe'
    'rust_lib_dan_player.dll' = 'build\windows\x64\runner\Release\rust_lib_dan_player.dll'
    'data\app.so' = 'build\windows\x64\runner\Release\data\app.so'
    'desktop_lyric\desktop_lyric.exe' = 'third_party\desktop_lyric\build\windows\x64\runner\Release\desktop_lyric.exe'
    'desktop_lyric\data\app.so' = 'third_party\desktop_lyric\build\windows\x64\runner\Release\data\app.so'
    'DESKTOP-EXPERIENCE.md' = 'docs\desktop-experience-26.0.3.md'
    'SETTINGS-BACKGROUNDS.md' = 'docs\settings-backgrounds.md'
    'LYRIC-EXPERIENCE.md' = 'docs\lyric-experience-26.0.3.md'
    'VALIDATION.md' = ('docs\' + $receipt.Version + '-validation.md')
    'CLASSIFICATION.md' = 'docs\library-categories.md'
    'classification-readonly-qa.md' = 'docs\classification-readonly-qa.md'
    'TASKBAR-LYRICS.md' = 'docs\taskbar-lyrics-feasibility.md'
    'INTERACTION-FIXES.md' = 'docs\interaction-regression-20260830.md'
    'OWNED-LYRIC-WINDOW.md' = 'docs\desktop-lyric-owned-palette.md'
    'ui-polish-26.0.3.md' = 'docs\ui-polish-26.0.3.md'
    'lyric-emphasis-spectrum-notes.md' = 'docs\lyric-emphasis-spectrum-notes.md'
    'online-sources.md' = 'docs\online-sources.md'
    'song-comments-notes.md' = 'docs\song-comments-notes.md'
    'APPLICATION-UPDATES.md' = 'docs\application-updates.md'
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
try {
    foreach ($line in $checksums) {
        if (-not $line) { continue }
        if ($line -notmatch '^([a-f0-9]{64})  (.+)$') { throw 'Malformed payload checksum line.' }
        $expected = $Matches[1]
        $name = $Matches[2]
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
$signatures = foreach ($relative in @('Dan Player.exe', 'rust_lib_dan_player.dll', 'desktop_lyric\desktop_lyric.exe')) {
    $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $payload $relative)
    if ($UnsignedCandidate) {
        if ($signature.Status.ToString() -ne 'NotSigned' -or $null -ne $signature.SignerCertificate) {
            throw "Local unsigned candidate contains a signed/stale/invalid own binary: $relative"
        }
        [pscustomobject]@{ File = $relative; Status = 'NotSigned'; Subject = $null }
        continue
    }
    if ($null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Thumbprint -ne 'E11D145A3C0D7298F4D3E96BADC497E360CAF510' -or
        $signature.Status.ToString() -in @('NotSigned', 'HashMismatch', 'NotSupported')) {
        throw "Signature missing, changed, or invalid: $relative"
    }
    [pscustomobject]@{
        File = $relative
        Subject = $signature.SignerCertificate.Subject
        Expires = $signature.SignerCertificate.NotAfter.ToString('o')
        Status = $signature.Status.ToString()
        StatusMessage = $signature.StatusMessage
    }
}
[pscustomobject]@{
    Passed = $true
    Version = $receipt.Version
    UnsignedCandidate = [bool]$UnsignedCandidate
    ZipPath = $zipPath
    ZipBytes = (Get-Item -LiteralPath $zipPath).Length
    ZipSha256 = $receipt.ZipSha256
    CheckedPayloadEntries = $checked
    SourceAndBuildMatches = $sourcePairs.Count
    Signatures = @($signatures)
}
