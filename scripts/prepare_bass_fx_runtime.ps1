#requires -Version 5.1
<#
.SYNOPSIS
Prepares the pinned, unmodified BASS_FX 2.4.12.6 x64 tempo extension.
.DESCRIPTION
BASS_FX is an unsigned third-party extension linked by the official BASS site.
Its exact archive and DLL SHA-256 are verified independently of the signed
UN4SEEN core. This script does not weaken prepare_bass_runtime.ps1, execute the
DLL, sign vendor files, install anything, or overwrite different cached bytes.
The complete original archive is retained for redistribution with its notices.
#>
[CmdletBinding()]
param(
    [string] $CacheRoot,
    [switch] $Offline,
    [switch] $VerifyOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repositoryRoot
$toolRoot = [IO.Path]::GetFullPath((Join-Path $workspaceRoot 'tool'))
$ciToolRoot = [IO.Path]::GetFullPath((Join-Path $repositoryRoot 'tool'))
if (-not $CacheRoot) { $CacheRoot = Join-Path $toolRoot 'bass-fx' }
$CacheRoot = [IO.Path]::GetFullPath($CacheRoot)
if (-not $CacheRoot.StartsWith($toolRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -and
    -not $CacheRoot.StartsWith($ciToolRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The BASS_FX cache must be a dedicated directory under the workspace tool directory.'
}

$package = [pscustomobject]@{
    Name = 'BASS_FX'
    Version = '2.4.12.6'
    Url = 'https://www.un4seen.com/files/z/0/bass_fx24.zip'
    ArchiveSha256 = 'A4BAF602865941963127ACB15ED12627D108189F99C2757970432AE7DA0366CD'
    ArchiveBytes = 292189
    Dll = 'bass_fx.dll'
    DllSha256 = 'A6E1847EEF52D882B4137AF514D834C2E220DACEB417C821D1E502FB7A34C84A'
    NoticeSha256 = '6755A8555F0A77153EE752E0CD0ED22494FE2402094BDB4AE4EADCE4CE79D5E0'
    Authenticode = 'NotSigned; integrity is pinned to the original HTTPS archive'
}

function Assert-NoLinkedAncestors([string] $Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if (((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing a symlink/junction in the BASS_FX cache: $current"
            }
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }
}

function Assert-Hash([string] $Path, [string] $Hash) {
    Assert-NoLinkedAncestors $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Hash) {
        throw "Missing or modified BASS_FX file; refusing to replace it: $Path"
    }
}

function Ensure-Directory([string] $Path) {
    Assert-NoLinkedAncestors $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        if ($VerifyOnly) { throw "Missing BASS_FX runtime directory: $Path" }
        $null = New-Item -ItemType Directory -Path $Path -Force
    }
}

$archiveDirectory = Join-Path $CacheRoot 'archives'
$archivePath = Join-Path $archiveDirectory 'bass_fx24-2.4.12.6.zip'
$runtimeDirectory = Join-Path $CacheRoot 'runtime-x64'
$dllDirectory = Join-Path $runtimeDirectory 'BASS'
$noticeDirectory = Join-Path $runtimeDirectory 'BASS_FX-notices'
$dllPath = Join-Path $dllDirectory $package.Dll
$noticePath = Join-Path $noticeDirectory 'bass_fx.txt'

Assert-NoLinkedAncestors $CacheRoot
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    if ($Offline -or $VerifyOnly) { throw "BASS_FX archive is not cached: $archivePath" }
    Ensure-Directory $archiveDirectory
    $downloadPath = Join-Path $archiveDirectory ('download-' + [guid]::NewGuid().ToString('N') + '.partial')
    $oldProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $package.Url -OutFile $downloadPath -UseBasicParsing -TimeoutSec 120
        Assert-Hash $downloadPath $package.ArchiveSha256
        if ((Get-Item -LiteralPath $downloadPath).Length -ne $package.ArchiveBytes) {
            throw 'BASS_FX archive size does not match the reviewed package.'
        }
        # The final path did not exist; never force replacement of another file.
        Move-Item -LiteralPath $downloadPath -Destination $archivePath
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $oldProtocol
    }
}
Assert-Hash $archivePath $package.ArchiveSha256
if ((Get-Item -LiteralPath $archivePath).Length -ne $package.ArchiveBytes) {
    throw 'BASS_FX archive length changed.'
}

$archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $archive.Entries) {
        $name = $entry.FullName.Replace('\', '/')
        if ($name.StartsWith('/') -or $name.Contains(':') -or
            ($name.Split('/') -contains '..') -or -not $names.Add($name)) {
            throw "Unsafe or duplicate archive member: $name"
        }
    }
    foreach ($item in @(
        @{ Entry = 'x64/bass_fx.dll'; Path = $dllPath; Hash = $package.DllSha256 },
        @{ Entry = 'bass_fx.txt'; Path = $noticePath; Hash = $package.NoticeSha256 }
    )) {
        $entry = $archive.GetEntry($item.Entry)
        if (-not $entry) { throw "BASS_FX package is missing $($item.Entry)" }
        Assert-NoLinkedAncestors $item.Path
        if (-not (Test-Path -LiteralPath $item.Path)) {
            if ($VerifyOnly) { throw "BASS_FX has not been prepared: $($item.Path)" }
            Ensure-Directory (Split-Path -Parent $item.Path)
            $source = $entry.Open()
            $target = $null
            try {
                $target = [IO.File]::Open($item.Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
                $source.CopyTo($target)
            } finally {
                if ($target) { $target.Dispose() }
                $source.Dispose()
            }
        }
        Assert-Hash $item.Path $item.Hash
    }
} finally { $archive.Dispose() }

$reader = [IO.BinaryReader]::new([IO.File]::OpenRead($dllPath))
try {
    if ($reader.ReadUInt16() -ne 0x5A4D) { throw 'BASS_FX DLL has no DOS header.' }
    $reader.BaseStream.Position = 0x3C
    $peOffset = $reader.ReadUInt32()
    if ($peOffset -gt $reader.BaseStream.Length - 26) { throw 'Truncated BASS_FX PE header.' }
    $reader.BaseStream.Position = $peOffset
    if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) {
        throw 'BASS_FX must be the AMD64 build.'
    }
    $reader.BaseStream.Position = $peOffset + 24
    if ($reader.ReadUInt16() -ne 0x020B) { throw 'BASS_FX must be PE32+.' }
} finally { $reader.Dispose() }
$info = [Diagnostics.FileVersionInfo]::GetVersionInfo($dllPath)
$version = '{0}.{1}.{2}.{3}' -f $info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart, $info.FilePrivatePart
if ($version -ne $package.Version) { throw "Unexpected BASS_FX version: $version" }

$provenance = @"
# BASS_FX tempo extension

Original project: https://www.jobnik.org/
Official BASS add-on listing: https://www.un4seen.com/bass.html
Archive: $($package.Url)
Archive SHA-256: $($package.ArchiveSha256)
x64 DLL version: $($package.Version)
x64 DLL SHA-256: $($package.DllSha256)
The original DLL is unsigned. It was hash-verified, not re-signed or installed.
The archive's historical readme/header identifies 2.4.12.1; the shipped x64 DLL
reports 2.4.12.6. Both original files are preserved without modification.

See bass_fx.txt for the original licence/disclaimer. The complete, unmodified
bass_fx24-2.4.12.6.zip is also included; no separate charge is made for BASS_FX.
This extension does not replace the BASS core's separate licensing conditions.
"@

[pscustomobject]@{
    RuntimeDirectory = $runtimeDirectory
    DllPath = $dllPath
    NoticePath = $noticePath
    ArchivePath = $archivePath
    Package = $package
    ProvenanceText = $provenance + "`n"
}
