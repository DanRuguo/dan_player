#requires -Version 5.1
<# Read-only production installer/payload verification. Never runs Setup. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string] $BuildReceiptPath,
    [Parameter(Mandatory=$true)][string] $PayloadDirectory,
    [Parameter(Mandatory=$true)][string] $NativeDirectory,
    [switch] $RequireSigned,
    [string] $SigningThumbprint = $env:RCEIT_SIGNING_THUMBPRINT
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$build = Get-Content -LiteralPath $BuildReceiptPath -Raw | ConvertFrom-Json
$config = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $BuildReceiptPath) 'build-config.iss') -Raw
if ($build.QaBuild -or $config -match '#define Qa|native_qa' -or $build.Installer -match '-QA\.exe$') {
    throw 'Refusing a QA installer as a release.'
}
function Hash([string] $Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
$native = Join-Path $NativeDirectory 'dan_installer_native.dll'
$cleanup = Join-Path $NativeDirectory 'dan_installer_cleanup.exe'
if ((Hash $native) -ne $build.NativeLibrarySha256) { throw 'Production installer DLL changed after packaging.' }
$exe = Get-Item -LiteralPath $build.Installer
if ($exe.VersionInfo.ProductName.Trim() -ne 'Dan Player Installer' -or
    $exe.VersionInfo.ProductVersion.Trim() -ne $build.Version -or
    (Hash $exe.FullName) -ne $build.Sha256) { throw 'Installer product/version/hash mismatch.' }
$checksum = (Get-Content -LiteralPath $build.ChecksumFile -Raw).TrimEnd("`r", "`n")
if ($checksum -cne ($build.Sha256 + '  ' + $exe.Name)) {
    throw 'Installer companion checksum must name the flat uploaded asset.'
}
$payload = (Resolve-Path -LiteralPath $PayloadDirectory).Path.TrimEnd('\', '/')
$lines = @(Get-Content -LiteralPath $build.Manifest)
if ($lines.Count -lt 3 -or $lines[0] -ne 'DANPLAYER_PAYLOAD_V1' -or $lines[1] -ne $build.Version) {
    throw 'Invalid runtime manifest header.'
}
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($line in $lines | Select-Object -Skip 2) {
    $fields = $line -split "`t"
    if ($fields.Count -ne 3 -or $fields[0] -notmatch '^[0-9a-f]{64}$' -or
        $fields[1] -notmatch '^\d+$' -or -not $seen.Add($fields[2])) {
        throw 'Invalid or duplicate runtime manifest record.'
    }
    $relative = $fields[2]
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '[:*?"<>|\x00-\x1f]' -or
        $relative -match '(^|[\\/])\.\.?([\\/]|$)') { throw 'Unsafe manifest path.' }
    $file = if ($relative -eq '.dan-player-install/cleanup.exe') { $cleanup } else {
        $resolved = [IO.Path]::GetFullPath((Join-Path $payload $relative))
        if (-not $resolved.StartsWith($payload + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest escaped payload.' }
        $resolved
    }
    if ((Get-Item -LiteralPath $file).Length -ne [long]$fields[1] -or (Hash $file) -ne $fields[0]) {
        throw "Runtime payload differs from packaged bytes: $relative"
    }
}
if ($seen.Count -ne $build.PayloadFiles -or
    $seen.Count -ne @(Get-ChildItem -LiteralPath $payload -Recurse -File -Force).Count + 1 -or
    (-not $seen.Contains('native_assets.json') -and
     -not $seen.Contains('data/flutter_assets/NativeAssetsManifest.json'))) { throw 'Incomplete payload coverage.' }
$signatures = @()
if ($RequireSigned) {
    if (-not $build.Signed) { throw 'Build receipt is not signed.' }
    $playerSignature = Get-AuthenticodeSignature -LiteralPath (Join-Path $payload 'Dan Player.exe')
    if (-not $playerSignature.SignerCertificate) { throw 'The audited player has no publisher signature.' }
    $expected = $playerSignature.SignerCertificate.Thumbprint
    if ($SigningThumbprint -and $expected -ne $SigningThumbprint.Replace(' ', '')) { throw 'Unexpected player signing certificate.' }
    foreach ($file in @((Join-Path $payload 'Dan Player.exe'), $exe.FullName, $native, $cleanup)) {
        $signature = Get-AuthenticodeSignature -LiteralPath $file
        if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $expected -or
            $signature.Status.ToString() -in @('NotSigned', 'HashMismatch', 'NotSupportedFileFormat', 'Incompatible')) {
            throw "Installer signature is missing or differs from the player: $file"
        }
        $signatures += [pscustomobject]@{
            File=[IO.Path]::GetFileName($file); Subject=$signature.SignerCertificate.Subject;
            Status=$signature.Status.ToString(); Timestamped=($null -ne $signature.TimeStamperCertificate)
        }
    }
}
[pscustomobject]@{
    Passed=$true; Version=$build.Version; Installer=$exe.FullName; Sha256=$build.Sha256;
    VerifiedManifestEntries=$seen.Count; CompanionChecksumVerified=$true;
    Signatures=$signatures; InstallationExecuted=$false
}
