# Source-only check shared by the unsigned build and portable assembler.
function Get-ReleaseYamlScalar([string] $Text, [string] $Key, [int] $Indent, [string] $Source) {
    $prefix = ' ' * $Indent
    $entries = [regex]::Matches($Text, ('(?m)^' + $prefix + [regex]::Escape($Key) + ':([^\r\n]*)\r?$'))
    if ($entries.Count -ne 1) { throw "Exactly one $Key entry is required in $Source." }
    $value = $entries[0].Groups[1].Value.Trim()
    if ($value -match '^"([^"\r\n]*)"$' -or $value -match "^'([^'\r\n]*)'$") {
        return $Matches[1]
    }
    if ($value -notmatch '^[A-Za-z0-9_./+\\-]+$') { throw "A plain $Key value is required in $Source." }
    return $value
}

function Get-ReleaseYamlBlock([string] $Text, [string] $Key, [int] $Indent, [string] $Source) {
    $lines = [regex]::Split($Text, '\r?\n')
    $prefix = '^' + (' ' * $Indent) + [regex]::Escape($Key) + ':'
    $starts = @(for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $prefix) { $i }
    })
    if ($starts.Count -ne 1 -or $lines[$starts[0]] -notmatch ($prefix + '[ \t]*$')) {
        throw "Exactly one plain $Key mapping is required in $Source."
    }
    $body = [Collections.Generic.List[string]]::new()
    for ($i = $starts[0] + 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line.Trim().Length -eq 0 -or $line.TrimStart().StartsWith('#')) { continue }
        $spaces = [regex]::Match($line, '^ *').Length
        if ($spaces -le $Indent) { break }
        $body.Add($line)
    }
    return $body -join "`n"
}

function Get-ReleasePubspecVersion([string] $Text, [string] $Source) {
    $value = Get-ReleaseYamlScalar $Text 'version' 0 $Source
    if ($value -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?(?:\+[0-9]+)?$' -or
        [regex]::Matches($Text, '(?m)^version:[ \t]*[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?(?:\+[0-9]+)?[ \t]*\r?$').Count -ne 1) {
        throw "Exactly one plain semantic version is required in $Source."
    }
    return $value
}

function Get-ReleaseVersionInfo([string] $RepositoryRoot) {
    $pubspec = [IO.File]::ReadAllText((Join-Path $RepositoryRoot 'pubspec.yaml'))
    $version = Get-ReleasePubspecVersion $pubspec 'pubspec.yaml'
    $settings = [IO.File]::ReadAllText((Join-Path $RepositoryRoot 'lib\app_settings.dart'))
    $displayEntries = [regex]::Matches($settings, '(?m)^\s*static\s+const\s+String\s+version\s*=')
    $displayVersions = [regex]::Matches($settings, '(?m)^\s*static\s+const\s+String\s+version\s*=\s*[''"]([^''"]+)[''"]\s*;')
    if ($displayEntries.Count -ne 1 -or $displayVersions.Count -ne 1) { throw 'Exactly one AppSettings.version string is required for release display-version verification.' }
    $displayVersion = $displayVersions[0].Groups[1].Value
    if ($displayVersion -cne $version) {
        throw "Release version mismatch: pubspec.yaml=$version, AppSettings.version=$displayVersion. Synchronize the displayed version before building or packaging."
    }

    $desktopRelativePath = 'third_party/desktop_lyric'
    if ([regex]::Matches($pubspec, '(?m)^  desktop_lyric:').Count -ne 1) {
        throw 'Exactly one desktop_lyric dependency is required, without a substituting override.'
    }
    $dependencies = Get-ReleaseYamlBlock $pubspec 'dependencies' 0 'pubspec.yaml'
    $desktopDependency = Get-ReleaseYamlBlock $dependencies 'desktop_lyric' 2 'pubspec.yaml dependencies'
    if ((Get-ReleaseYamlScalar $desktopDependency 'path' 4 'pubspec.yaml desktop_lyric') -cne $desktopRelativePath) {
        throw "desktop_lyric must use the repository path $desktopRelativePath."
    }
    $desktopPubspec = [IO.File]::ReadAllText((Join-Path $RepositoryRoot "$desktopRelativePath/pubspec.yaml"))
    if ((Get-ReleaseYamlScalar $desktopPubspec 'name' 0 'desktop_lyric pubspec.yaml') -cne 'desktop_lyric') {
        throw 'The desktop_lyric path must contain the desktop_lyric package.'
    }
    $desktopVersion = Get-ReleasePubspecVersion $desktopPubspec 'desktop_lyric pubspec.yaml'

    $lock = [IO.File]::ReadAllText((Join-Path $RepositoryRoot 'pubspec.lock'))
    $packages = Get-ReleaseYamlBlock $lock 'packages' 0 'pubspec.lock'
    $lockedDesktop = Get-ReleaseYamlBlock $packages 'desktop_lyric' 2 'pubspec.lock packages'
    $description = Get-ReleaseYamlBlock $lockedDesktop 'description' 4 'pubspec.lock desktop_lyric'
    if ((Get-ReleaseYamlScalar $lockedDesktop 'source' 4 'pubspec.lock desktop_lyric') -cne 'path' -or
        (Get-ReleaseYamlScalar $description 'relative' 6 'pubspec.lock desktop_lyric description') -cne 'true' -or
        (Get-ReleaseYamlScalar $description 'path' 6 'pubspec.lock desktop_lyric description') -cne $desktopRelativePath) {
        throw "pubspec.lock must retain the relative desktop_lyric path $desktopRelativePath."
    }
    $lockedVersion = Get-ReleaseYamlScalar $lockedDesktop 'version' 4 'pubspec.lock desktop_lyric'
    if ($desktopVersion -cne $version -or $lockedVersion -cne $version) {
        throw "Release version mismatch: main=$version, desktop_lyric=$desktopVersion, pubspec.lock=$lockedVersion. Synchronize all release versions before building or packaging."
    }
    return [pscustomobject]@{ Version = $version; DisplayVersion = $displayVersion }
}
