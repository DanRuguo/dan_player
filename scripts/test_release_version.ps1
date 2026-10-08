[CmdletBinding()]
param([string] $FixtureRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'support/release_version.ps1')
$repo = Split-Path -Parent $PSScriptRoot
$qaRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $repo) 'tool/qa-local'))
if (-not $FixtureRoot) { $FixtureRoot = Join-Path $qaRoot 'release-version-tests' }
$fixtureParent = [IO.Path]::GetFullPath($FixtureRoot)
$allowedPrefix = $qaRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if (-not $fixtureParent.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Release-version fixtures must stay below the workspace tool/qa-local directory.'
}
$null = New-Item -ItemType Directory -Path $fixtureParent -Force
$temporary = Join-Path $fixtureParent ('case-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporary
$utf8 = [Text.UTF8Encoding]::new($false)
$checks = 0
$failures = [Collections.Generic.List[string]]::new()

function Write-Fixture([string] $Root, [string] $Relative, [string] $Contents) {
    $file = Join-Path $Root $Relative
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force
    [IO.File]::WriteAllText($file, $Contents, $utf8)
}

function New-VersionFixture([string] $Version = '26.1.1') {
    $root = Join-Path $temporary ([Guid]::NewGuid().ToString('N'))
    Write-Fixture $root 'pubspec.yaml' @"
name: dan_player
version: $Version
dependencies:
  desktop_lyric:
    path: third_party/desktop_lyric
"@
    Write-Fixture $root 'lib/app_settings.dart' "class AppSettings {`n  static const String version = '$Version';`n}`n"
    Write-Fixture $root 'third_party/desktop_lyric/pubspec.yaml' "name: desktop_lyric`nversion: $Version`n"
    Write-Fixture $root 'pubspec.lock' @"
packages:
  desktop_lyric:
    dependency: "direct main"
    description:
      path: "third_party/desktop_lyric"
      relative: true
    source: path
    version: "$Version"
  unrelated:
    source: hosted
    version: "1.2.3"
"@
    return $root
}

function Change-Fixture([string] $Root, [string] $Relative, [string] $Before, [string] $After) {
    $file = Join-Path $Root $Relative
    $text = [IO.File]::ReadAllText($file)
    if (-not $text.Contains($Before)) { throw "Fixture substitution is missing: $Before" }
    Write-Fixture $Root $Relative ($text.Replace($Before, $After))
}

function Assert-Rejected([string] $Root) {
    $rejected = $false
    try { $null = Get-ReleaseVersionInfo $Root } catch { $rejected = $true }
    if (-not $rejected) { throw 'An inconsistent release source was accepted.' }
}

function Run-VersionCase([string] $Name, [scriptblock] $Action) {
    $script:checks++
    try {
        & $Action
        Write-Output "PASS $Name"
    } catch {
        $script:failures.Add($Name)
        Write-Output "FAIL ${Name}: $($_.Exception.Message)"
    }
}

try {
    Run-VersionCase 'four synchronized versions retain the existing return contract' {
        $info = Get-ReleaseVersionInfo (New-VersionFixture)
        if ($info.Version -cne '26.1.1' -or $info.DisplayVersion -cne '26.1.1' -or
            @($info.PSObject.Properties).Count -ne 2) { throw 'The release return contract changed.' }
    }
    Run-VersionCase 'synchronized prerelease and build metadata remain valid' {
        $info = Get-ReleaseVersionInfo (New-VersionFixture '26.1.1-snapshot.2+17')
        if ($info.Version -cne '26.1.1-snapshot.2+17') { throw 'The full version was lost.' }
    }
    foreach ($relative in @('pubspec.yaml', 'lib/app_settings.dart', 'third_party/desktop_lyric/pubspec.yaml', 'pubspec.lock')) {
        Run-VersionCase "missing required file $relative" {
            $root = New-VersionFixture
            Remove-Item -LiteralPath (Join-Path $root $relative)
            Assert-Rejected $root
        }
    }
    foreach ($relative in @('pubspec.yaml', 'third_party/desktop_lyric/pubspec.yaml')) {
        Run-VersionCase "missing version in $relative" {
            $root = New-VersionFixture
            Change-Fixture $root $relative 'version: 26.1.1' ''
            Assert-Rejected $root
        }
        Run-VersionCase "duplicate version in $relative" {
            $root = New-VersionFixture
            Change-Fixture $root $relative 'version: 26.1.1' "version: 26.1.1`nversion: 26.1.1"
            Assert-Rejected $root
        }
        Run-VersionCase "malformed duplicate version in $relative" {
            $root = New-VersionFixture
            Change-Fixture $root $relative 'version: 26.1.1' "version: 26.1.1`nversion: invalid"
            Assert-Rejected $root
        }
    }
    Run-VersionCase 'mismatched AppSettings version' {
        $root = New-VersionFixture
        Change-Fixture $root 'lib/app_settings.dart' "version = '26.1.1'" "version = '26.0.6'"
        Assert-Rejected $root
    }
    Run-VersionCase 'missing AppSettings version' {
        $root = New-VersionFixture
        Change-Fixture $root 'lib/app_settings.dart' "static const String version = '26.1.1';" ''
        Assert-Rejected $root
    }
    Run-VersionCase 'malformed duplicate AppSettings version' {
        $root = New-VersionFixture
        Change-Fixture $root 'lib/app_settings.dart' "static const String version = '26.1.1';" "static const String version = '26.1.1';`nstatic const String version = versionFromElsewhere;"
        Assert-Rejected $root
    }
    Run-VersionCase 'mismatched desktop package version' {
        $root = New-VersionFixture
        Change-Fixture $root 'third_party/desktop_lyric/pubspec.yaml' 'version: 26.1.1' 'version: 26.0.6'
        Assert-Rejected $root
    }
    Run-VersionCase 'wrong desktop package identity' {
        $root = New-VersionFixture
        Change-Fixture $root 'third_party/desktop_lyric/pubspec.yaml' 'name: desktop_lyric' 'name: other_package'
        Assert-Rejected $root
    }
    Run-VersionCase 'missing desktop main dependency' {
        $root = New-VersionFixture
        Change-Fixture $root 'pubspec.yaml' '  desktop_lyric:' '  other_package:'
        Assert-Rejected $root
    }
    Run-VersionCase 'duplicate desktop main dependency' {
        $root = New-VersionFixture
        Change-Fixture $root 'pubspec.yaml' '  desktop_lyric:' "  desktop_lyric:`n    path: third_party/desktop_lyric`n  desktop_lyric:"
        Assert-Rejected $root
    }
    Run-VersionCase 'desktop dependency override cannot substitute another package' {
        $root = New-VersionFixture
        $pubspec = [IO.File]::ReadAllText((Join-Path $root 'pubspec.yaml'))
        Write-Fixture $root 'pubspec.yaml' ($pubspec + "`ndependency_overrides:`n  desktop_lyric:`n    path: another/desktop_lyric`n")
        Assert-Rejected $root
    }
    Run-VersionCase 'mismatched desktop main dependency path' {
        $root = New-VersionFixture
        Change-Fixture $root 'pubspec.yaml' 'path: third_party/desktop_lyric' 'path: another/desktop_lyric'
        Assert-Rejected $root
    }
    Run-VersionCase 'duplicate desktop main dependency path' {
        $root = New-VersionFixture
        Change-Fixture $root 'pubspec.yaml' '    path: third_party/desktop_lyric' "    path: third_party/desktop_lyric`n    path: another/desktop_lyric"
        Assert-Rejected $root
    }
    Run-VersionCase 'missing desktop locked entry' {
        $root = New-VersionFixture
        Change-Fixture $root 'pubspec.lock' '  desktop_lyric:' '  other_package:'
        Assert-Rejected $root
    }
    Run-VersionCase 'duplicate desktop locked entry' {
        $root = New-VersionFixture
        Change-Fixture $root 'pubspec.lock' '  desktop_lyric:' "  desktop_lyric:`n    source: path`n    version: `"26.1.1`"`n  desktop_lyric:"
        Assert-Rejected $root
    }
    Run-VersionCase 'malformed duplicate desktop locked entry' {
        $root = New-VersionFixture
        Change-Fixture $root 'pubspec.lock' '  desktop_lyric:' "  desktop_lyric: invalid`n  desktop_lyric:"
        Assert-Rejected $root
    }
    Run-VersionCase 'duplicate desktop lock description' {
        $root = New-VersionFixture
        Change-Fixture $root 'pubspec.lock' '    description:' "    description: invalid`n    description:"
        Assert-Rejected $root
    }
    Run-VersionCase 'mismatched desktop locked version' {
        $root = New-VersionFixture
        Change-Fixture $root 'pubspec.lock' 'version: "26.1.1"' 'version: "26.0.6"'
        Assert-Rejected $root
    }
    Run-VersionCase 'missing desktop locked version' {
        $root = New-VersionFixture
        Change-Fixture $root 'pubspec.lock' '    version: "26.1.1"' ''
        Assert-Rejected $root
    }
    Run-VersionCase 'duplicate desktop locked version' {
        $root = New-VersionFixture
        Change-Fixture $root 'pubspec.lock' '    version: "26.1.1"' "    version: `"26.1.1`"`n    version: `"26.0.6`""
        Assert-Rejected $root
    }
    Run-VersionCase 'mismatched desktop locked relative path' {
        $root = New-VersionFixture
        Change-Fixture $root 'pubspec.lock' 'path: "third_party/desktop_lyric"' 'path: "another/desktop_lyric"'
        Assert-Rejected $root
    }
    Run-VersionCase 'missing desktop locked path' {
        $root = New-VersionFixture
        Change-Fixture $root 'pubspec.lock' '      path: "third_party/desktop_lyric"' ''
        Assert-Rejected $root
    }
    Run-VersionCase 'duplicate desktop locked path' {
        $root = New-VersionFixture
        Change-Fixture $root 'pubspec.lock' '      path: "third_party/desktop_lyric"' "      path: `"third_party/desktop_lyric`"`n      path: `"another/desktop_lyric`""
        Assert-Rejected $root
    }
    Run-VersionCase 'non-relative desktop lock description' {
        $root = New-VersionFixture
        Change-Fixture $root 'pubspec.lock' 'relative: true' 'relative: false'
        Assert-Rejected $root
    }
    Run-VersionCase 'hosted desktop lock source cannot replace the path package' {
        $root = New-VersionFixture
        Change-Fixture $root 'pubspec.lock' '    source: path' '    source: hosted'
        Assert-Rejected $root
    }
    Write-Output "Release-version checks: $checks total, $($checks - $failures.Count) passed, $($failures.Count) failed."
    if ($failures.Count) { throw "Release-version fixture failures: $($failures -join ', ')" }
} finally {
    $resolved = (Get-Item -LiteralPath $temporary).FullName
    if (-not $resolved.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not [IO.Path]::GetFileName($resolved).StartsWith('case-') -or
        (Get-Item -LiteralPath $temporary).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
        throw 'Refusing fixture cleanup outside the workspace QA directory.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
