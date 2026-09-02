#requires -Version 5.1
<#
.SYNOPSIS
Downloads and verifies the pinned official UN4SEEN Windows x64 runtime.
.DESCRIPTION
Archives are cached under the workspace tool directory. A changed upstream
archive, wrong architecture, unexpected file, or damaged cache is an error;
the script never silently updates a hash or overwrites an existing runtime.
No DLL is executed, installed, or re-signed.
.EXAMPLE
./scripts/prepare_bass_runtime.ps1
.EXAMPLE
./scripts/prepare_bass_runtime.ps1 -Offline -VerifyOnly
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
Add-Type -AssemblyName System.Net.Http

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repositoryRoot
if (-not $CacheRoot) { $CacheRoot = Join-Path $workspaceRoot 'tool\bass' }
$CacheRoot = [IO.Path]::GetFullPath($CacheRoot)
$runtimeDirectory = Join-Path $CacheRoot 'runtime-x64-9pkg'

# Pin both the complete official archive and the exact x64 DLL copied from it.
# These values match the official downloads inspected through 2026-09-02. Updating a
# version requires an explicit review of the new archive and its licence text.
$packages = @(
    [pscustomobject]@{
        Name = 'BASS'; Version = '2.4.18.3'; Archive = 'bass24.zip'; Dll = 'bass.dll'; Notice = 'bass.txt'
        Url = 'https://www.un4seen.com/files/bass24.zip'; ArchiveSize = 957484
        ArchiveSha256 = '3A03EC9A33D0F4F9D167660DA51C8BB1432E8977496995455AB137277D69636E'
        DllSha256 = 'FEBB2CF1882D554C3A958280777DA0B69F07DE6E262DF271DE11C56E4A54AFD4'
    }
    [pscustomobject]@{
        Name = 'BASSWASAPI'; Version = '2.4.4.1'; Archive = 'basswasapi24.zip'; Dll = 'basswasapi.dll'; Notice = 'basswasapi.txt'
        Url = 'https://www.un4seen.com/files/basswasapi24.zip'; ArchiveSize = 151147
        ArchiveSha256 = '4BA99200EBEF8DCA11CC99CBA9B5DC3E51A1C467E570DE2CBC0631A038F7EA2D'
        DllSha256 = '6F0869C11431E01F759FBE1CD6080299C833C519EB8AB1FEAE12106907B1FBD1'
    }
    [pscustomobject]@{
        Name = 'BASSMIX'; Version = '2.4.12'; Archive = 'bassmix24.zip'; Dll = 'bassmix.dll'; Notice = 'bassmix.txt'
        Url = 'https://www.un4seen.com/files/bassmix24.zip'; ArchiveSize = 157731
        ArchiveSha256 = 'C22D3D6135B5D14AF23AE1D54100BE6C30FE500D9B0F253B5EBC7E9130DBAD85'
        DllSha256 = 'F782CAE8090700A456C9E7AEAA7770C3B90CB60A1E765C4B3CBAE739D3B4D58D'
    }
    [pscustomobject]@{
        Name = 'BASSAPE'; Version = '2.4.1'; Archive = 'bassape24.zip'; Dll = 'bassape.dll'; Notice = 'bassape.txt'
        Url = 'https://www.un4seen.com/files/bassape24.zip'; ArchiveSize = 115224
        ArchiveSha256 = '39AED2E9AC240253DE0ECA37D261715B85CC7937504447083E2ED6690256B770'
        DllSha256 = '3638177A4FEC909C85C378EA327FEB67D26A3D50011B3F8B7DDAC6D2A0D5BB25'
    }
    [pscustomobject]@{
        Name = 'BASSDSD'; Version = '2.4.2'; Archive = 'bassdsd24.zip'; Dll = 'bassdsd.dll'; Notice = 'bassdsd.txt'
        Url = 'https://www.un4seen.com/files/bassdsd24.zip'; ArchiveSize = 55058
        ArchiveSha256 = '9E77EF048FA9BED4466A62B61CD5781CEB932FA8BEB2E144306DCA46CCDE445F'
        DllSha256 = '2FB0FA095CC04046185FF572689EC0B74BAA3124A907E7BE3796AABFDB1A266F'
    }
    [pscustomobject]@{
        Name = 'BASSFLAC'; Version = '2.4.6.1'; Archive = 'bassflac24.zip'; Dll = 'bassflac.dll'; Notice = 'bassflac.txt'
        Url = 'https://www.un4seen.com/files/bassflac24.zip'; ArchiveSize = 105507
        ArchiveSha256 = '147280210F62A80E52094E1822E73A16FD3B1A8C9C857C24DCCA7DCFCB4FFA14'
        DllSha256 = '09EFD682CEA33E58EA7A892942D36BDE5963218596E6AD68F17807FB57F069CD'
    }
    [pscustomobject]@{
        Name = 'BASSMIDI'; Version = '2.4.16'; Archive = 'bassmidi24.zip'; Dll = 'bassmidi.dll'; Notice = 'bassmidi.txt'
        Url = 'https://www.un4seen.com/files/bassmidi24.zip'; ArchiveSize = 338453
        ArchiveSha256 = '317EC770D71266B5294543D7C87CBBB39ABA38BC8BC623AF518A96C670392234'
        DllSha256 = 'E04E334CA35DCE657B11EB9DACC7561B9C1365C337C1C3ABAC90A36336405EE6'
    }
    [pscustomobject]@{
        Name = 'BASSOPUS'; Version = '2.4.3.3'; Archive = 'bassopus24.zip'; Dll = 'bassopus.dll'; Notice = 'bassopus.txt'
        Url = 'https://www.un4seen.com/files/bassopus24.zip'; ArchiveSize = 189640
        ArchiveSha256 = '1FB6E033289EA968CA1FD02DEA154A2E5D06BB9C2E33CDEDA277E63084D9AD20'
        DllSha256 = 'AF0E891CC923BD685A1CDDE2842838458D0218AFA0FDFD919A5E4582B6AB239B'
    }
    [pscustomobject]@{
        Name = 'BASSWV'; Version = '2.4.7.4'; Archive = 'basswv24.zip'; Dll = 'basswv.dll'; Notice = 'basswv.txt'
        Url = 'https://www.un4seen.com/files/basswv24.zip'; ArchiveSize = 103751
        ArchiveSha256 = '813801639BB140FA8F6BAA8AA03AEAC47225E1E876FE943367F91C38F79C1ECA'
        DllSha256 = '7021C3B48E1D9085BBF2839860A6C5D816981A7B0405BAF6963725FF55EF24C4'
    }
)

function Assert-NotReparsePoint([string] $Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing a symlink or junction in the BASS cache: $Path"
    }
}

function Assert-ChildPath([string] $Path, [string] $Parent) {
    $prefix = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes its expected directory: $fullPath"
    }
}

function Assert-Hash([string] $Path, [string] $ExpectedHash) {
    Assert-NotReparsePoint $Path
    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actualHash -ne $ExpectedHash) {
        throw "SHA-256 mismatch for $Path. Expected $ExpectedHash; found $actualHash. Existing files were not replaced."
    }
}

function Assert-Amd64Pe([string] $Path) {
    Assert-NotReparsePoint $Path
    $reader = [IO.BinaryReader]::new([IO.File]::OpenRead($Path))
    try {
        if ($reader.BaseStream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) {
            throw "Not a PE file: $Path"
        }
        $reader.BaseStream.Position = 0x3C
        $peOffset = $reader.ReadUInt32()
        if ($peOffset -gt $reader.BaseStream.Length - 26) { throw "Truncated PE header: $Path" }
        $reader.BaseStream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550 -or $reader.ReadUInt16() -ne 0x8664) {
            throw "Expected an AMD64 (x64) PE file: $Path"
        }
        $reader.BaseStream.Position = $peOffset + 24
        if ($reader.ReadUInt16() -ne 0x020B) { throw "Expected a PE32+ x64 image: $Path" }
    } finally {
        $reader.Dispose()
    }
}

function Assert-OfficialDownloadUri([uri] $Uri) {
    if ($Uri.Scheme -ne 'https' -or $Uri.DnsSafeHost -notin @('www.un4seen.com', 'un4seen.com') -or
        $Uri.Port -ne 443 -or $Uri.UserInfo -or $Uri.Query -or $Uri.Fragment -or
        $Uri.AbsolutePath -notmatch '^/files/[a-z0-9]+\.zip$') {
        throw "Refusing a non-official or non-HTTPS BASS download: $Uri"
    }
}

function Receive-OfficialArchive($Package, [string] $Destination) {
    $partialPath = Join-Path $CacheRoot (".{0}.{1}.part" -f $Package.Archive, [guid]::NewGuid().ToString('N'))
    Assert-ChildPath $partialPath $CacheRoot
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $handler.UseCookies = $false
    $handler.UseDefaultCredentials = $false
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromMinutes(2)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('DanPlayer-runtime-preparation/26.0.3')
    $timeout = [Threading.CancellationTokenSource]::new([TimeSpan]::FromMinutes(2))
    $response = $null
    try {
        $uri = [uri] $Package.Url
        for ($redirect = 0; $redirect -le 5; $redirect++) {
            Assert-OfficialDownloadUri $uri
            $response = $client.GetAsync($uri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead, $timeout.Token).GetAwaiter().GetResult()
            $status = [int] $response.StatusCode
            if ($status -ge 300 -and $status -lt 400) {
                if ($redirect -eq 5 -or -not $response.Headers.Location) { throw 'Invalid or excessive BASS download redirects.' }
                $uri = [uri]::new($uri, $response.Headers.Location)
                $response.Dispose()
                $response = $null
                continue
            }
            $null = $response.EnsureSuccessStatusCode()
            break
        }
        if ($response.Content.Headers.ContentLength -and
            $response.Content.Headers.ContentLength -ne $Package.ArchiveSize) {
            throw "The official $($Package.Archive) size has changed; review the pinned release before updating it."
        }
        $source = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $target = $null
        try {
            $target = [IO.File]::Open($partialPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $buffer = New-Object byte[] 65536
            $total = 0L
            while (($count = $source.ReadAsync($buffer, 0, $buffer.Length, $timeout.Token).GetAwaiter().GetResult()) -gt 0) {
                $total += $count
                if ($total -gt $Package.ArchiveSize) { throw "The $($Package.Archive) download exceeded its pinned size." }
                $target.Write($buffer, 0, $count)
            }
            if ($total -ne $Package.ArchiveSize) { throw "The $($Package.Archive) download was incomplete." }
        } finally {
            if ($target) { $target.Dispose() }
            $source.Dispose()
        }
        Assert-Hash $partialPath $Package.ArchiveSha256
        Assert-ChildPath $Destination $CacheRoot
        if (Test-Path -LiteralPath $Destination) { throw "Refusing to replace a concurrently created cache file: $Destination" }
        Move-Item -LiteralPath $partialPath -Destination $Destination
    } finally {
        if ($response) { $response.Dispose() }
        $timeout.Dispose()
        $client.Dispose()
        $handler.Dispose()
        # Only this invocation's incomplete file can be removed, never a cache.
        if (Test-Path -LiteralPath $partialPath -PathType Leaf) {
            Assert-ChildPath $partialPath $CacheRoot
            Remove-Item -LiteralPath $partialPath
        }
    }
}

function Get-RequiredZipEntry($Archive, [string] $EntryName) {
    $entries = @($Archive.Entries | Where-Object { $_.FullName -ceq $EntryName })
    if ($entries.Count -ne 1 -or $entries[0].Length -le 0) {
        throw "Expected exactly one non-empty archive entry: $EntryName"
    }
    return $entries[0]
}

function Get-ZipEntryHash($Entry) {
    $stream = $Entry.Open()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Copy-ZipEntry($Entry, [string] $Destination) {
    $source = $Entry.Open()
    $target = $null
    try {
        $target = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $source.CopyTo($target)
    } finally {
        if ($target) { $target.Dispose() }
        $source.Dispose()
    }
}

function Assert-Runtime([string] $Directory) {
    Assert-NotReparsePoint $Directory
    $dllDirectory = Join-Path $Directory 'BASS'
    $noticeDirectory = Join-Path $Directory 'UN4SEEN-notices'
    foreach ($subdirectory in @($dllDirectory, $noticeDirectory)) { Assert-NotReparsePoint $subdirectory }
    $dllFiles = @(Get-ChildItem -LiteralPath $dllDirectory -Force)
    $noticeFiles = @(Get-ChildItem -LiteralPath $noticeDirectory -Force)
    if ($dllFiles.Count -ne $packages.Count -or $noticeFiles.Count -ne $packages.Count) {
        throw "Unexpected or missing files in the BASS runtime: $Directory"
    }
    foreach ($package in $packages) {
        $dllPath = Join-Path $dllDirectory $package.Dll
        Assert-Hash $dllPath $package.DllSha256
        Assert-Amd64Pe $dllPath
        $signature = Get-AuthenticodeSignature -LiteralPath $dllPath
        if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or
            $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Un4seen Developments Ltd(?:,|$)') {
            throw "The BASS DLL lacks a valid original UN4SEEN signature: $dllPath"
        }
        if ($package.Name -eq 'BASS') {
            $fileVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($dllPath)
            $bassVersion = [version]::new($fileVersion.FileMajorPart, $fileVersion.FileMinorPart, $fileVersion.FileBuildPart, $fileVersion.FilePrivatePart)
            if ($bassVersion -lt [version] '2.4.18.0') { throw 'Dan Player requires BASS 2.4.18 or newer.' }
        }
        $archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $CacheRoot $package.Archive))
        try {
            $notice = Get-RequiredZipEntry $archive $package.Notice
            Assert-Hash (Join-Path $noticeDirectory $package.Notice) (Get-ZipEntryHash $notice)
        } finally { $archive.Dispose() }
    }
}

if (-not (Test-Path -LiteralPath $CacheRoot -PathType Container)) {
    if ($VerifyOnly) { throw "BASS cache is missing: $CacheRoot" }
    $null = New-Item -ItemType Directory -Path $CacheRoot
}
Assert-NotReparsePoint $CacheRoot

# HttpClient on Windows PowerShell 5.1 may otherwise negotiate obsolete TLS.
$previousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
try {
    [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    foreach ($package in $packages) {
        $archivePath = Join-Path $CacheRoot $package.Archive
        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
            if ($Offline -or $VerifyOnly) { throw "Missing pinned archive in offline mode: $archivePath" }
            Write-Host "Downloading $($package.Name) $($package.Version) from UN4SEEN..."
            Receive-OfficialArchive $package $archivePath
        }
        Assert-Hash $archivePath $package.ArchiveSha256
        if ((Get-Item -LiteralPath $archivePath).Length -ne $package.ArchiveSize) { throw "Unexpected archive size: $archivePath" }
    }
} finally {
    [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
}

if (-not (Test-Path -LiteralPath $runtimeDirectory -PathType Container)) {
    if ($VerifyOnly) { throw "BASS runtime is missing: $runtimeDirectory" }
    $stagingDirectory = Join-Path $CacheRoot ("runtime-x64-9pkg.{0}.staging" -f [guid]::NewGuid().ToString('N'))
    Assert-ChildPath $stagingDirectory $CacheRoot
    $null = New-Item -ItemType Directory -Path $stagingDirectory
    $null = New-Item -ItemType Directory -Path (Join-Path $stagingDirectory 'BASS')
    $null = New-Item -ItemType Directory -Path (Join-Path $stagingDirectory 'UN4SEEN-notices')
    try {
        foreach ($package in $packages) {
            $archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $CacheRoot $package.Archive))
            try {
                # Extract only two explicitly named entries into controlled paths;
                # no archive-provided path is used as a filesystem destination.
                Copy-ZipEntry (Get-RequiredZipEntry $archive ("x64/" + $package.Dll)) (Join-Path (Join-Path $stagingDirectory 'BASS') $package.Dll)
                Copy-ZipEntry (Get-RequiredZipEntry $archive $package.Notice) (Join-Path (Join-Path $stagingDirectory 'UN4SEEN-notices') $package.Notice)
            } finally { $archive.Dispose() }
        }
        Assert-Runtime $stagingDirectory
        Assert-ChildPath (Resolve-Path -LiteralPath $stagingDirectory).Path $CacheRoot
        Assert-ChildPath $runtimeDirectory $CacheRoot
        if (Test-Path -LiteralPath $runtimeDirectory) { throw "Refusing to overwrite an existing runtime: $runtimeDirectory" }
        Move-Item -LiteralPath $stagingDirectory -Destination $runtimeDirectory
    } catch {
        Write-Warning "The failed staging directory was retained for inspection: $stagingDirectory"
        throw
    }
}
Assert-Runtime $runtimeDirectory

$provenance = [Collections.Generic.List[string]]::new()
$provenance.Add('# UN4SEEN BASS x64 runtime provenance')
$provenance.Add('')
$provenance.Add('Pinned official HTTPS archives reviewed through 2026-09-02. DLLs and original TXT notices are copied byte-for-byte; no signature is added or changed.')
$provenance.Add('Official download page: https://www.un4seen.com/bass.html')
$provenance.Add('')
$provenance.Add('| Package | Version | Official archive | Archive SHA-256 | DLL SHA-256 |')
$provenance.Add('| --- | --- | --- | --- | --- |')
foreach ($package in $packages) {
    $provenance.Add("| $($package.Name) | $($package.Version) | $($package.Url) | $($package.ArchiveSha256) | $($package.DllSha256) |")
}
$provenance.Add('')
$provenance.Add('Every DLL is verified as PE32+ machine 0x8664 (AMD64) with a valid original UN4SEEN Authenticode signature. Dan Player requires BASS 2.4.18 or newer; this manifest pins 2.4.18.3. The adjacent original TXT notices contain the licence, requirements, history and warranty terms.')
$provenance.Add('BASS permits non-commercial use under its own terms; commercial use requires the appropriate licence. Redistributors must review the original terms and the licences of the application and its other dependencies before publishing a package.')

Write-Host "Verified all nine UN4SEEN x64 runtime DLLs and original notices: $runtimeDirectory"
[pscustomobject]@{
    CacheDirectory = $CacheRoot
    RuntimeDirectory = $runtimeDirectory
    Packages = $packages
    ProvenanceText = ($provenance -join "`n") + "`n"
}
