#requires -Version 5.1
<#
.SYNOPSIS
Assembles already-built Windows x64 releases into a new portable ZIP.
.DESCRIPTION
This script does not build, install, sign, or publish anything. It verifies the
offline BASS cache, copies the shared main app/desktop lyrics release into a new dist run
directory, adds unmodified Visual Studio app-local CRT files and licence
notices, then writes payload and ZIP SHA256SUMS files. Existing output folders
are never replaced or recursively deleted.
.EXAMPLE
./scripts/prepare_bass_runtime.ps1
./scripts/assemble_windows_release.ps1
#>
[CmdletBinding()]
param(
    [string] $MainReleaseDirectory,
    [string] $DesktopLyricReleaseDirectory,
    [string] $BassCacheRoot,
    [string] $BassFxCacheRoot,
    [string] $OutputRoot,
    [string] $VcRuntimeDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repositoryRoot
. (Join-Path $PSScriptRoot 'support\release_version.ps1')
$releaseVersion = Get-ReleaseVersionInfo $repositoryRoot
if (-not $MainReleaseDirectory) { $MainReleaseDirectory = Join-Path $repositoryRoot 'build\windows\x64\runner\Release' }
if ($DesktopLyricReleaseDirectory) {
    # Parameter retained for existing callers; lyrics now run from the main AOT.
    Write-Host 'DesktopLyricReleaseDirectory is ignored: packaging uses Dan Player.exe --desktop-lyric and one shared runtime.'
}
if (-not $BassCacheRoot) { $BassCacheRoot = Join-Path $workspaceRoot 'tool\bass' }
if (-not $BassFxCacheRoot) { $BassFxCacheRoot = Join-Path $workspaceRoot 'tool\bass-fx' }
if (-not $OutputRoot) { $OutputRoot = Join-Path $workspaceRoot 'dist' }

function Assert-NotReparsePoint([string] $Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing a symlink or junction in a release input/output: $Path"
    }
}

function Assert-TreeHasNoReparsePoints([string] $Directory) {
    Assert-NotReparsePoint $Directory
    $pending = [Collections.Generic.Queue[string]]::new()
    $pending.Enqueue($Directory)
    while ($pending.Count -gt 0) {
        foreach ($item in Get-ChildItem -LiteralPath ($pending.Dequeue()) -Force) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing a symlink or junction in a release tree: $($item.FullName)"
            }
            if ($item.PSIsContainer) { $pending.Enqueue($item.FullName) }
        }
    }
}

function Assert-Amd64Pe([string] $Path) {
    $reader = [IO.BinaryReader]::new([IO.File]::OpenRead($Path))
    try {
        if ($reader.BaseStream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { throw "Not a PE file: $Path" }
        $reader.BaseStream.Position = 0x3C
        $peOffset = $reader.ReadUInt32()
        if ($peOffset -gt $reader.BaseStream.Length - 26) { throw "Truncated PE header: $Path" }
        $reader.BaseStream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550 -or $reader.ReadUInt16() -ne 0x8664) {
            throw "Expected an AMD64 (x64) PE file: $Path"
        }
        $reader.BaseStream.Position = $peOffset + 24
        if ($reader.ReadUInt16() -ne 0x020B) { throw "Expected a PE32+ x64 image: $Path" }
    } finally { $reader.Dispose() }
}

function Resolve-ReleaseDirectory([string] $Directory, [string] $Executable) {
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { throw "Build the release before packaging: $Directory" }
    $resolved = (Resolve-Path -LiteralPath $Directory).Path
    Assert-TreeHasNoReparsePoints $resolved
    foreach ($relativePath in @($Executable, 'flutter_windows.dll', 'data\icudtl.dat')) {
        if (-not (Test-Path -LiteralPath (Join-Path $resolved $relativePath) -PathType Leaf)) {
            throw "Incomplete release; missing $relativePath in $resolved"
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $resolved 'data\flutter_assets') -PathType Container)) {
        throw "Incomplete Flutter assets in $resolved"
    }
    foreach ($file in Get-ChildItem -LiteralPath $resolved -Recurse -File -Force) {
        if ($file.Extension.ToLowerInvariant() -in @('.exe', '.dll')) { Assert-Amd64Pe $file.FullName }
    }
    return $resolved
}

function Assert-ZipEntryHash($Archive, [string] $EntryName, [string] $ExpectedHash) {
    $entry = $Archive.GetEntry($EntryName)
    if (-not $entry) { throw "ZIP is missing audited font/AOT asset: $EntryName" }
    $stream = $entry.Open()
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $actualHash = -join ($hasher.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') })
        if ($actualHash -ne $ExpectedHash) { throw "ZIP font/AOT hash mismatch: $EntryName" }
    } finally {
        $hasher.Dispose()
        $stream.Dispose()
    }
}

function Assert-ZipFontAudit($Archive, [string] $BundlePrefix, [string] $ReportPath) {
    $audit = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
    if ($audit.schemaVersion -ne 1 -or $audit.passed -ne $true) { throw 'Invalid staged font audit.' }
    Assert-ZipEntryHash $Archive ($BundlePrefix + 'data/app.so') $audit.aotSha256
    Assert-ZipEntryHash $Archive ($BundlePrefix + 'data/flutter_assets/FontManifest.json') $audit.fontManifestSha256
    foreach ($font in $audit.fonts) {
        Assert-ZipEntryHash $Archive ($BundlePrefix + 'data/flutter_assets/' + $font.asset) $font.sha256
    }
    foreach ($asset in $audit.sourceAssets) {
        Assert-ZipEntryHash $Archive ($BundlePrefix + 'data/flutter_assets/' + $asset.asset) $asset.sha256
    }
    Assert-ZipEntryHash $Archive ($BundlePrefix + 'FONT-INTEGRITY.json') (Get-FileHash -LiteralPath $ReportPath -Algorithm SHA256).Hash
}

function Find-VcRuntimeDirectory {
    if ($VcRuntimeDirectory) { return (Resolve-Path -LiteralPath $VcRuntimeDirectory).Path }
    $redistRoots = [Collections.Generic.List[string]]::new()
    if ($env:VCToolsRedistDir) { $redistRoots.Add($env:VCToolsRedistDir) }
    if ($env:VCINSTALLDIR) { $redistRoots.Add((Join-Path $env:VCINSTALLDIR 'Redist\MSVC')) }
    $redistRoots.Add((Join-Path $workspaceRoot 'tool\vs-buildtools\VC\Redist\MSVC'))

    $vswhere = $null
    if (${env:ProgramFiles(x86)}) {
        $candidate = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $vswhere = $candidate }
    }
    if ($vswhere) {
        $installations = @(& $vswhere -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
        if ($LASTEXITCODE -ne 0) { throw 'Visual Studio discovery failed.' }
        foreach ($installation in $installations) {
            if ($installation) { $redistRoots.Add((Join-Path $installation 'VC\Redist\MSVC')) }
        }
    }

    $candidates = [Collections.Generic.List[object]]::new()
    foreach ($root in ($redistRoots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $versionDirectories = @((Get-Item -LiteralPath $root)) + @(Get-ChildItem -LiteralPath $root -Directory)
        foreach ($versionDirectory in $versionDirectories) {
            $version = $null
            if (-not [version]::TryParse($versionDirectory.Name, [ref] $version)) { continue }
            $x64Directory = Join-Path $versionDirectory.FullName 'x64'
            if (-not (Test-Path -LiteralPath $x64Directory -PathType Container)) { continue }
            foreach ($crt in Get-ChildItem -LiteralPath $x64Directory -Directory -Filter 'Microsoft.VC*.CRT') {
                $candidates.Add([pscustomobject]@{ Version = $version; Path = $crt.FullName })
            }
        }
    }
    $selected = $candidates | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $selected) {
        throw 'No Visual Studio x64 app-local CRT was found. Pass -VcRuntimeDirectory pointing to VC\Redist\MSVC\<version>\x64\Microsoft.VC*.CRT; do not copy DLLs from System32.'
    }
    return $selected.Path
}

function Copy-FileUnchanged([string] $Source, [string] $Destination) {
    $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    if (Test-Path -LiteralPath $Destination) {
        if (-not (Test-Path -LiteralPath $Destination -PathType Leaf) -or
            (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ne $sourceHash) {
            throw "Refusing to overwrite a different staged file: $Destination"
        }
    } else {
        Copy-Item -LiteralPath $Source -Destination $Destination
    }
    if ((Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ne $sourceHash) {
        throw "Copied file failed byte-for-byte verification: $Destination"
    }
}

function Copy-ReleaseTree([string] $Source, [string] $Destination, [string[]] $ExcludeNames) {
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($item.Name -in $ExcludeNames) { continue }
        $destinationPath = Join-Path $Destination $item.Name
        if (Test-Path -LiteralPath $destinationPath) { throw "Unexpected staged path already exists: $destinationPath" }
        Copy-Item -LiteralPath $item.FullName -Destination $destinationPath -Recurse -Force
    }
}

function Write-NewUtf8File([string] $Path, [string] $Text) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
    try { $writer.Write($Text) } finally { $writer.Dispose() }
}

function Write-PortableZip([string] $Directory, [string] $Destination, [string] $RootName) {
    $prefix = $Directory.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $stream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $archive = $null
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true, [Text.Encoding]::UTF8)
        # Windows PowerShell 5.1 can make ZipFile.CreateFromDirectory emit legacy
        # backslashes. Explicit ZIP entry names preserve portable '/' separators
        # and UTF-8 names on both .NET Framework and modern PowerShell.
        $null = $archive.CreateEntry($RootName + '/')
        foreach ($item in Get-ChildItem -LiteralPath $Directory -Recurse -Force | Sort-Object FullName) {
            $relativePath = $item.FullName.Substring($prefix.Length).Replace('\', '/')
            $entryName = $RootName + '/' + $relativePath
            if ($item.PSIsContainer) {
                $null = $archive.CreateEntry($entryName + '/')
            } else {
                $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $item.FullName, $entryName, [IO.Compression.CompressionLevel]::Optimal)
            }
        }
    } finally {
        if ($archive) { $archive.Dispose() }
        $stream.Dispose()
    }
}

$MainReleaseDirectory = Resolve-ReleaseDirectory $MainReleaseDirectory 'Dan Player.exe'
if (-not (Test-Path -LiteralPath (Join-Path $MainReleaseDirectory 'rust_lib_dan_player.dll') -PathType Leaf)) {
    throw 'The main release is missing rust_lib_dan_player.dll.'
}
# Fail before creating a new dist directory if an incrementally built binary
# still carries fonts subsetted for an older kernel. This is read-only.
$fontVerifier = Join-Path $PSScriptRoot 'verify_windows_release_fonts.ps1'
& $fontVerifier -ProjectRoot $repositoryRoot -ReleaseDirectory $MainReleaseDirectory

$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
foreach ($inputDirectory in @($MainReleaseDirectory)) {
    $inputPrefix = $inputDirectory.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($OutputRoot.Equals($inputDirectory, [StringComparison]::OrdinalIgnoreCase) -or
        $OutputRoot.StartsWith($inputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The output directory must not be inside the release input tree.'
    }
}

$version = $releaseVersion.Version
$packageStem = 'DanPlayer-{0}-windows-x64' -f $version.Replace('+', '-')

# Assembly is deliberately offline: downloading is an explicit separate step.
$bass = & (Join-Path $PSScriptRoot 'prepare_bass_runtime.ps1') -CacheRoot $BassCacheRoot -Offline -VerifyOnly
$bassFx = & (Join-Path $PSScriptRoot 'prepare_bass_fx_runtime.ps1') -CacheRoot $BassFxCacheRoot -Offline -VerifyOnly
$crtDirectory = Find-VcRuntimeDirectory
Assert-TreeHasNoReparsePoints $crtDirectory
if ((Split-Path -Leaf $crtDirectory) -notmatch '^Microsoft\.VC14[0-9]+\.CRT$' -or
    (Split-Path -Leaf (Split-Path -Parent $crtDirectory)) -ne 'x64') {
    throw "Expected a Visual Studio x64 CRT redistribution directory: $crtDirectory"
}
$crtFiles = @(Get-ChildItem -LiteralPath $crtDirectory -File -Filter '*.dll' | Sort-Object Name)
if ($crtFiles.Count -eq 0) { throw "No app-local CRT DLLs were found in $crtDirectory" }
foreach ($requiredCrt in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if ($requiredCrt -notin $crtFiles.Name) { throw "Missing required app-local CRT file: $requiredCrt" }
}
$crtManifest = @(
    foreach ($file in $crtFiles) {
        Assert-Amd64Pe $file.FullName
        $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
        if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or
            $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
            throw "The Visual Studio CRT file lacks a valid original Microsoft signature: $($file.FullName)"
        }
        [pscustomobject]@{
            File = $file.Name
            Version = $file.VersionInfo.FileVersion
            Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            Signer = $signature.SignerCertificate.Subject
        }
    }
)

if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) { $null = New-Item -ItemType Directory -Path $OutputRoot }
Assert-NotReparsePoint $OutputRoot
$runName = '{0}-{1}-{2}' -f $packageStem, [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'), [guid]::NewGuid().ToString('N').Substring(0, 8)
$releaseDirectory = Join-Path $OutputRoot $runName
$null = New-Item -ItemType Directory -Path $releaseDirectory
$payloadDirectory = Join-Path $releaseDirectory $packageStem
$null = New-Item -ItemType Directory -Path $payloadDirectory

try {
    # Build outputs may already have manually staged BASS/helper/CRT files for
    # QA. Always use the separately verified originals for those paths.
    $mainExclusions = @('BASS', 'desktop_lyric', 'desktop_lyric.exe', 'desktop_lyric.pdb', 'DESKTOP-LYRIC-MODE', 'UN4SEEN-notices', 'FONT-INTEGRITY.json') + @($crtFiles.Name)
    Copy-ReleaseTree $MainReleaseDirectory $payloadDirectory $mainExclusions
    Write-NewUtf8File (Join-Path $payloadDirectory 'DESKTOP-LYRIC-MODE') "shared-executable-v1`n"
    Copy-Item -LiteralPath (Join-Path $bass.RuntimeDirectory 'BASS') -Destination (Join-Path $payloadDirectory 'BASS') -Recurse
    Copy-FileUnchanged $bassFx.DllPath (Join-Path $payloadDirectory 'BASS\bass_fx.dll')

    foreach ($file in $crtFiles) {
        Copy-FileUnchanged $file.FullName (Join-Path $payloadDirectory $file.Name)
    }

    $licenceDirectory = Join-Path $payloadDirectory 'licenses'
    $un4seenDirectory = Join-Path $licenceDirectory 'UN4SEEN'
    $microsoftDirectory = Join-Path $licenceDirectory 'Microsoft-CRT'
    $bassFxDirectory = Join-Path $licenceDirectory 'BASS_FX'
    $null = New-Item -ItemType Directory -Path $licenceDirectory
    $null = New-Item -ItemType Directory -Path $microsoftDirectory
    $null = New-Item -ItemType Directory -Path $bassFxDirectory
    Copy-FileUnchanged $bassFx.NoticePath (Join-Path $bassFxDirectory 'bass_fx.txt')
    Copy-FileUnchanged $bassFx.ArchivePath (Join-Path $bassFxDirectory 'bass_fx24-2.4.12.6.zip')
    Write-NewUtf8File (Join-Path $bassFxDirectory 'PROVENANCE.md') $bassFx.ProvenanceText
    Copy-Item -LiteralPath (Join-Path $bass.RuntimeDirectory 'UN4SEEN-notices') -Destination $un4seenDirectory -Recurse
    Write-NewUtf8File (Join-Path $un4seenDirectory 'PROVENANCE.md') $bass.ProvenanceText
    Copy-FileUnchanged (Join-Path $repositoryRoot 'LICENSE') (Join-Path $payloadDirectory 'LICENSE')
    $redistNotice = $null
    if ($crtDirectory -match '^(.*)[\\/]VC[\\/]Redist[\\/]MSVC[\\/]') {
        $vsLicences = Join-Path $Matches[1] 'Licenses'
        if (Test-Path -LiteralPath $vsLicences -PathType Container) {
            $redistNotice = Get-ChildItem -LiteralPath $vsLicences -Recurse -File -Filter 'Redist.txt' |
                Sort-Object FullName | Select-Object -First 1
        }
    }
    if ($redistNotice) { Copy-FileUnchanged $redistNotice.FullName (Join-Path $microsoftDirectory 'VS-Redist.txt') }
    $crtNotice = @'
Microsoft Visual C++ app-local runtime

The DLLs listed in BUILD-PROVENANCE.json were copied unchanged from the installed
Visual Studio x64 redistribution directory. Their original Microsoft signatures
were verified and were not replaced. One copy is placed beside Dan Player.exe.
Windows 10/11 provide the Universal CRT; no system DLLs are copied from System32.

Redistribution is subject to the applicable Visual Studio licence and REDIST list:
https://learn.microsoft.com/cpp/windows/redistributing-visual-cpp-files
https://aka.ms/vs/17/redist.txt

App-local CRT copies are not serviced independently by Windows Update. Refresh
the verified Visual Studio runtime when rebuilding future application releases.
'@
    Write-NewUtf8File (Join-Path $microsoftDirectory 'README.txt') ($crtNotice + "`n")

    $revision = 'unknown'
    $workingTreeDirty = $null
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $revisionOutput = & git -C $repositoryRoot rev-parse HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $revisionOutput -match '^[0-9a-f]{40}$') {
            $revision = $revisionOutput
            $dirtyOutput = @(& git -C $repositoryRoot status --porcelain 2>$null)
            if ($LASTEXITCODE -eq 0) { $workingTreeDirty = $dirtyOutput.Count -gt 0 }
        }
    }
    $buildProvenance = [ordered]@{
        Product = 'Dan Player'
        Version = $version
        DisplayVersion = $releaseVersion.DisplayVersion
        Architecture = 'windows-x64'
        AssembledUtc = [DateTime]::UtcNow.ToString('o')
        SourceProject = 'https://github.com/DanRuguo/dan_player'
        SourceRevision = $revision
        WorkingTreeDirty = $workingTreeDirty
        SigningPerformedByAssembler = $false
        DesktopLyricMode = 'shared-executable-v1'
        DesktopLyricLaunch = 'Dan Player.exe --desktop-lyric (independent process)'
        FontIntegrityReports = @('FONT-INTEGRITY.json')
        Bass = @($bass.Packages | Select-Object Name, Version, Url, ArchiveSha256, Dll, DllSha256)
        BassFx = $bassFx.Package
        MicrosoftCrt = $crtManifest
    }
    Write-NewUtf8File (Join-Path $payloadDirectory 'BUILD-PROVENANCE.json') (($buildProvenance | ConvertTo-Json -Depth 8) + "`n")

    $portableReadme = @"
Dan Player $version - Windows x64 portable package

Extract the entire ZIP into a writable folder, then run "Dan Player.exe".
Keep BASS, data, and DESKTOP-LYRIC-MODE beside the main executable. Desktop lyrics
run as a separate process using "Dan Player.exe --desktop-lyric", sharing the same
Flutter assets and app-local Microsoft CRT DLLs with the player.

This assembler does not install software, change Windows settings, sign files,
or publish a release. Any existing application signatures are preserved.
SHA256SUMS inside this folder covers the payload; SHA256SUMS next to the ZIP
covers the complete archive. Hashes detect changes but are not a publisher signature.

Original licences/notices are in LICENSE and licenses/. BASS has its own usage
and commercial licensing terms. Before public distribution, review all licences
and make the exact corresponding application source available as required.
Source project: https://github.com/DanRuguo/dan_player
Build revision: $revision
Working tree modified: $workingTreeDirty
"@
    Write-NewUtf8File (Join-Path $payloadDirectory 'PORTABLE-README.txt') ($portableReadme + "`n")

    # Recheck the copied vendor bytes, not only their source cache.
    foreach ($package in $bass.Packages) {
        $copiedDll = Join-Path (Join-Path $payloadDirectory 'BASS') $package.Dll
        if ((Get-FileHash -LiteralPath $copiedDll -Algorithm SHA256).Hash -ne $package.DllSha256) {
            throw "Staged BASS DLL failed verification: $copiedDll"
        }
    }
    # Recheck the actual staged fonts and record exact required codepoints.
    # The final ZIP is checked against these reports below, not just by size.
    $mainFontReport = Join-Path $payloadDirectory 'FONT-INTEGRITY.json'
    & $fontVerifier -ProjectRoot $repositoryRoot -ReleaseDirectory $payloadDirectory -ReportPath $mainFontReport
    $payloadPrefix = $payloadDirectory.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $payloadChecksums = @(
        foreach ($file in Get-ChildItem -LiteralPath $payloadDirectory -Recurse -File -Force | Sort-Object FullName) {
            $relativePath = $file.FullName.Substring($payloadPrefix.Length).Replace('\', '/')
            '{0}  {1}' -f (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $relativePath
        }
    )
    Write-NewUtf8File (Join-Path $payloadDirectory 'SHA256SUMS') (($payloadChecksums -join "`n") + "`n")

    $zipPath = Join-Path $releaseDirectory ($packageStem + '.zip')
    Write-PortableZip $payloadDirectory $zipPath $packageStem
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        foreach ($requiredEntry in @('Dan Player.exe', 'DESKTOP-LYRIC-MODE', 'flutter_windows.dll', 'rust_lib_dan_player.dll', 'data/app.so', 'data/icudtl.dat', 'BASS/basswasapi.dll', 'BASS/bassmix.dll', 'licenses/UN4SEEN/bass.txt', 'licenses/UN4SEEN/bassmix.txt', 'BASS/bass_fx.dll', 'licenses/BASS_FX/bass_fx24-2.4.12.6.zip', 'DESKTOP-EXPERIENCE.md', 'BUILD-PROVENANCE.json', 'SHA256SUMS')) {
            if (-not $zip.GetEntry($packageStem + '/' + $requiredEntry)) { throw "ZIP is missing $requiredEntry" }
        }
        Assert-ZipFontAudit $zip ($packageStem + '/') $mainFontReport
        if (@($zip.Entries | Where-Object {
            $_.FullName.StartsWith($packageStem + '/desktop_lyric/', [StringComparison]::OrdinalIgnoreCase) -or
            $_.FullName.Equals($packageStem + '/desktop_lyric.exe', [StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0) { throw 'Shared-executable ZIP contains a legacy desktop lyrics helper.' }
        Assert-ZipEntryHash $zip ($packageStem + '/DESKTOP-LYRIC-MODE') (Get-FileHash -LiteralPath (Join-Path $payloadDirectory 'DESKTOP-LYRIC-MODE') -Algorithm SHA256).Hash
        Assert-ZipEntryHash $zip ($packageStem + '/BASS/bass_fx.dll') $bassFx.Package.DllSha256
        Assert-ZipEntryHash $zip ($packageStem + '/licenses/BASS_FX/bass_fx24-2.4.12.6.zip') $bassFx.Package.ArchiveSha256
        Assert-ZipEntryHash $zip ($packageStem + '/licenses/BASS_FX/bass_fx.txt') $bassFx.Package.NoticeSha256
    } finally { $zip.Dispose() }

    $checksumPath = Join-Path $releaseDirectory 'SHA256SUMS'
    $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-NewUtf8File $checksumPath ("{0}  {1}`n" -f $zipHash, [IO.Path]::GetFileName($zipPath))
    Write-Host "Portable release assembled without replacing any previous output: $releaseDirectory"
    [pscustomobject]@{
        Version = $version
        DisplayVersion = $releaseVersion.DisplayVersion
        DesktopLyricMode = 'shared-executable-v1'
        OutputDirectory = $releaseDirectory
        PackageDirectory = $payloadDirectory
        ZipPath = $zipPath
        ChecksumPath = $checksumPath
        ZipSha256 = $zipHash
    }
} catch {
    Write-Warning "The new, incomplete output was retained for inspection; older releases are untouched: $releaseDirectory"
    throw
}
