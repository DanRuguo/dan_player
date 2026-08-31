#requires -Version 5.1
<#
.SYNOPSIS
Builds an offline Inno installer from an already audited portable directory.
.DESCRIPTION
No installation, publishing, or Flutter build is performed. Signing is opt-in.
Native DLL and cleanup EXE must already be built. With -Sign, those two native
outputs are signed before packaging, then Setup is signed before its checksum.
Outputs are new directories. Source assets and portable payload are unchanged.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string] $PayloadDirectory,
    [string] $NativeDirectory,
    [string] $Compiler,
    [string] $OutputRoot,
    [switch] $Sign,
    [string] $SigningThumbprint = $env:RCEIT_SIGNING_THUMBPRINT,
    [string] $TimestampServer,
    [switch] $QaBuild,
    [ValidateSet('system','light','dark')][string] $QaTheme = 'system',
    [ValidateSet(0,7,9,11,14)][int] $QaDialogFontSize = 0
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Sign -and $QaBuild) { throw 'Fictional QA installers must not be signed.' }
if (-not $QaBuild -and $QaTheme -ne 'system') { throw 'Forced theme is available only in the fictional QA build.' }
if (-not $QaBuild -and $QaDialogFontSize -ne 0) { throw 'Forced font metrics are available only in the fictional QA build.' }
$installerRepository = Split-Path -Parent $PSScriptRoot
$installerWorkspace = Split-Path -Parent $installerRepository
if (-not $NativeDirectory) { $NativeDirectory = Join-Path $installerWorkspace 'tool\qa-installer\build\Release' }
if (-not $Compiler) { $Compiler = Join-Path $installerWorkspace 'tool\inno-7.1.0\ISCC.exe' }
if (-not $OutputRoot) { $OutputRoot = Join-Path $installerWorkspace 'tool\qa-installer\packages' }
if (-not (Test-Path -LiteralPath $Compiler -PathType Leaf)) { throw 'An existing Inno Setup 7.1 compiler is required; this script never downloads or installs it.' }
$compilerVersion = (& $Compiler --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $compilerVersion -ne '7.1.0') { throw "Expected reviewed Inno Setup 7.1.0; found $compilerVersion" }

function Assert-InstallerPath([string] $Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $itemPath = $full
    while ($itemPath) {
        if (Test-Path -LiteralPath $itemPath) {
            if (((Get-Item -LiteralPath $itemPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Refusing a reparse point: $itemPath" }
        }
        $next = Split-Path -Parent $itemPath
        if ($next -eq $itemPath) { break }
        $itemPath = $next
    }
    return $full
}
function Assert-RelativePayloadPath([string] $Relative) {
    if (-not $Relative -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '[:*?"<>|\x00-\x1f]' -or $Relative -match '(^|[\\/])\.\.?([\\/]|$)') { throw "Unsafe payload path: $Relative" }
    foreach ($part in ($Relative -split '[\\/]')) {
        if ($part -match '[. ]$' -or $part -match '^(?i:con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\.|$)') { throw "Ambiguous Windows payload path: $Relative" }
    }
    if ([IO.Path]::GetExtension($Relative) -match '^(?i:\.mp3|\.flac|\.wav|\.m4a|\.ogg|\.lrc|\.db|\.sqlite|\.pfx|\.key)$') { throw "Private/media input is not an installer payload: $Relative" }
}
function Quote-Inno([string] $Value) { return '"' + $Value.Replace('"', '""') + '"' }
function Write-NewInstallerText([string] $Path, [string] $Value) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
    try { $writer.Write($Value) } finally { $writer.Dispose() }
}
function Assert-NativeManifest([string] $Library, [string] $Manifest) {
    # Use the exact DLL that Inno will embed. This pure reader has no target,
    # registry, known-folder, transaction, or installation side effects.
    $typeName = 'DanInstallerManifestGuard_' + [Guid]::NewGuid().ToString('N')
    $libraryLiteral = $Library.Replace('"', '""')
    $source = @"
using System.Runtime.InteropServices;
using System.Text;
public static class $typeName {
    [DllImport(@"$libraryLiteral", CharSet=CharSet.Unicode, CallingConvention=CallingConvention.StdCall, ExactSpelling=true)]
    public static extern int DP_ValidateManifest(string manifest);
    [DllImport(@"$libraryLiteral", CharSet=CharSet.Unicode, CallingConvention=CallingConvention.StdCall, ExactSpelling=true)]
    public static extern int DP_GetError(StringBuilder buffer, int capacity);
}
"@
    $guard = Add-Type -TypeDefinition $source -PassThru
    if ($guard::DP_ValidateManifest($Manifest) -ne 1) {
        $errorText = [Text.StringBuilder]::new(2048)
        $null = $guard::DP_GetError($errorText, $errorText.Capacity)
        throw "Runtime manifest policy rejected the payload before Inno compression: $errorText"
    }
}

$PayloadDirectory = Assert-InstallerPath ((Resolve-Path -LiteralPath $PayloadDirectory).Path)
$NativeDirectory = Assert-InstallerPath ((Resolve-Path -LiteralPath $NativeDirectory).Path)
$versionText = Get-Content -LiteralPath (Join-Path $installerRepository 'pubspec.yaml') -Raw
$match = [regex]::Match($versionText, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9]+)?)\s*$')
if (-not $match.Success) { throw 'Missing valid version in root pubspec.yaml' }
$installerVersion = $match.Groups[1].Value
$displayVersion = $installerVersion -replace '-snapshot\.(\d+)', ' snapshot$1'
$numericVersion = ($installerVersion -split '[-+]')[0] + '.0'
$nativeName = if ($QaBuild) { 'dan_installer_native_qa.dll' } else { 'dan_installer_native.dll' }
$nativeFile = Join-Path $NativeDirectory $nativeName
$cleanupFile = Join-Path $NativeDirectory 'dan_installer_cleanup.exe'
foreach ($file in @($nativeFile, $cleanupFile)) { if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Native build missing: $file" }; Assert-InstallerPath $file | Out-Null }
if ($Sign) {
    $signingOptions = @{}
    if ($SigningThumbprint) { $signingOptions.Thumbprint = $SigningThumbprint }
    if ($TimestampServer) { $signingOptions.TimestampServer = $TimestampServer }
    & (Join-Path $PSScriptRoot 'sign_windows_release.ps1') -Path @($nativeFile, $cleanupFile) @signingOptions
}

$files = @(Get-ChildItem -LiteralPath $PayloadDirectory -Recurse -File -Force | Sort-Object FullName)
if ($files.Count -eq 0 -or $files.Count -gt 20000) { throw 'Payload file count outside the supported budget' }
foreach ($item in Get-ChildItem -LiteralPath $PayloadDirectory -Recurse -Force) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Refusing payload link: $($item.FullName)" }
}
$payloadPrefix = $PayloadDirectory.TrimEnd('\', '/') + '\'
$entries = [Collections.Generic.List[object]]::new()
$known = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
$totalBytes = [uint64]0
foreach ($file in $files) {
    $relative = $file.FullName.Substring($payloadPrefix.Length).Replace('\', '/')
    Assert-RelativePayloadPath $relative
    if ($known.ContainsKey($relative)) { throw "Duplicate payload path: $relative" }
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $known.Add($relative, $hash)
    $entries.Add([pscustomobject]@{ Relative=$relative; Source=$file.FullName; Hash=$hash; Length=$file.Length })
    $totalBytes += $file.Length
}
if ($totalBytes -gt 8GB) { throw 'Payload exceeds 8 GiB safety budget' }
foreach ($required in @('Dan Player.exe','data/app.so','desktop_lyric/desktop_lyric.exe')) {
    if (-not $known.ContainsKey($required)) { throw "Incomplete player payload: $required" }
}
if (-not $QaBuild) {
    $provenancePath = Join-Path $PayloadDirectory 'BUILD-PROVENANCE.json'
    $provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
    if ($provenance.Product -ne 'Dan Player' -or $provenance.Version -ne $installerVersion -or $provenance.SourceProject -ne 'https://github.com/DanRuguo/dan_player') { throw 'Audited portable payload product/version does not match pubspec' }
    $checksums = Get-Content -LiteralPath (Join-Path $PayloadDirectory 'SHA256SUMS')
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in $checksums) {
        if ($line -notmatch '^([a-fA-F0-9]{64})  (.+)$') { throw 'Invalid portable SHA256SUMS record' }
        $expected = $Matches[1].ToLowerInvariant(); $relative = $Matches[2].Replace('\','/')
        Assert-RelativePayloadPath $relative
        if (-not $seen.Add($relative) -or -not $known.ContainsKey($relative) -or $known[$relative] -ne $expected) { throw "Portable payload hash mismatch: $relative" }
    }
    if ($seen.Count -ne $known.Count - 1) { throw 'Portable checksum manifest does not cover exactly every payload file except itself' }
}

$OutputRoot = Assert-InstallerPath $OutputRoot
$runDirectory = Join-Path $OutputRoot ('installer-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
$null = New-Item -ItemType Directory -Path $runDirectory
$entries.Add([pscustomobject]@{ Relative='.dan-player-install/cleanup.exe'; Source=$cleanupFile; Hash=(Get-FileHash -LiteralPath $cleanupFile -Algorithm SHA256).Hash.ToLowerInvariant(); Length=(Get-Item -LiteralPath $cleanupFile).Length })
$manifestFile = Join-Path $runDirectory 'payload.manifest'
$manifestText = "DANPLAYER_PAYLOAD_V1`n$installerVersion`n"
$fileEntries = [Collections.Generic.List[string]]::new()
foreach ($entry in $entries) {
    $manifestText += "{0}`t{1}`t{2}`n" -f $entry.Hash, $entry.Length, $entry.Relative
    $parent = [IO.Path]::GetDirectoryName($entry.Relative.Replace('/','\'))
    $destination = if ($parent) { '{app}\' + $parent } else { '{app}' }
    $installedPath = $destination + '\' + [IO.Path]::GetFileName($entry.Relative)
    $callback = "PayloadInstalled(ExpandConstant('" + $installedPath.Replace("'", "''") + "'))"
    $fileEntries.Add(('Source: {0}; DestDir: {1}; DestName: {2}; Flags: ignoreversion; Check: ContinueInstall; AfterInstall: {3}' -f (Quote-Inno $entry.Source), (Quote-Inno $destination), (Quote-Inno ([IO.Path]::GetFileName($entry.Relative))), $callback))
}
Write-NewInstallerText $manifestFile $manifestText
Assert-NativeManifest $nativeFile $manifestFile
$fileEntriesPath = Join-Path $runDirectory 'payload-files.iss'
Write-NewInstallerText $fileEntriesPath (($fileEntries -join "`n") + "`n")
$stem = 'DanPlayer-' + $installerVersion + '-Setup-x64' + $(if ($QaBuild) { '-QA' } else { '' })
$defines = [ordered]@{
    AppVersion=$installerVersion; DisplayVersion=$displayVersion; NumericVersion=$numericVersion;
    RepositoryRoot=$installerRepository; NativeLibrary=$nativeFile; ManifestFile=$manifestFile;
    PayloadFileEntries=$fileEntriesPath; OutputDirectory=$runDirectory; OutputFilename=$stem
}
$configText = ''
foreach ($entry in $defines.GetEnumerator()) { $configText += '#define ' + $entry.Key + ' ' + (Quote-Inno $entry.Value) + "`n" }
if ($QaBuild) { $configText += "#define QaBuild`n" }
if ($QaBuild -and $QaTheme -eq 'light') { $configText += "#define QaThemeLight`n" }
if ($QaBuild -and $QaTheme -eq 'dark') { $configText += "#define QaThemeDark`n" }
if ($QaBuild -and $QaDialogFontSize -gt 0) { $configText += "#define QaDialogFontSize $QaDialogFontSize`n" }
$configPath = Join-Path $runDirectory 'build-config.iss'
Write-NewInstallerText $configPath $configText
& $Compiler --no-ide-signtools "--define=BuildConfig=$configPath" (Join-Path $installerRepository 'installer\setup.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno compilation failed; retained inputs: $runDirectory" }
$executable = Join-Path $runDirectory ($stem + '.exe')
if ($Sign) {
    & (Join-Path $PSScriptRoot 'sign_windows_release.ps1') -Path @($executable) @signingOptions
}
$installerSha256 = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumFile = $executable + '.sha256'
# A Release asset has a flat basename, not our local installer-run subdirectory.
# This exact companion is selected before any optional aggregate SHA256SUMS.
Write-NewInstallerText $checksumFile ($installerSha256 + '  ' + [IO.Path]::GetFileName($executable) + "`n")
$result = [ordered]@{ Version=$installerVersion; DisplayVersion=$displayVersion; QaBuild=[bool]$QaBuild; Signed=[bool]$Sign; Installer=$executable; Sha256=$installerSha256; ChecksumFile=$checksumFile; PayloadFiles=$entries.Count; PayloadBytes=$totalBytes; CompilerVersion=$compilerVersion; Manifest=$manifestFile; NativeLibrarySha256=(Get-FileHash -LiteralPath $nativeFile -Algorithm SHA256).Hash.ToLowerInvariant() }
Write-NewInstallerText (Join-Path $runDirectory 'installer-build.json') (($result | ConvertTo-Json -Depth 4) + "`n")
[pscustomobject]$result
