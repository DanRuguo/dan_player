# Source-only check shared by the unsigned build and portable assembler.
function Get-ReleaseVersionInfo([string] $RepositoryRoot) {
    $pubspec = [IO.File]::ReadAllText((Join-Path $RepositoryRoot 'pubspec.yaml'))
    $versions = [regex]::Matches($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?(?:\+[0-9]+)?)\s*$')
    if ($versions.Count -ne 1) { throw 'Exactly one plain semantic version is required in pubspec.yaml.' }
    $settings = [IO.File]::ReadAllText((Join-Path $RepositoryRoot 'lib\app_settings.dart'))
    $displayVersions = [regex]::Matches($settings, '(?m)^\s*static\s+const\s+String\s+version\s*=\s*[''"]([^''"]+)[''"]\s*;')
    if ($displayVersions.Count -ne 1) { throw 'Exactly one AppSettings.version string is required for release display-version verification.' }
    $version = $versions[0].Groups[1].Value
    $displayVersion = $displayVersions[0].Groups[1].Value
    if ($displayVersion -cne $version) {
        throw "Release version mismatch: pubspec.yaml=$version, AppSettings.version=$displayVersion. Synchronize the displayed version before building or packaging."
    }
    return [pscustomobject]@{ Version = $version; DisplayVersion = $displayVersion }
}
