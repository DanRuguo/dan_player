#requires -Version 5.1

# Compare parsed JSON values, including property names and ordered arrays. A
# regenerated checksum is not evidence that the core kept the portable source.
function Assert-SlimInstallerJsonEqual {
    param($Expected, $Actual, [string] $Location = '$')
    if ($null -eq $Expected -or $null -eq $Actual) {
        if ($null -ne $Expected -or $null -ne $Actual) { throw "Slim provenance changed: $Location" }
        return
    }
    if ($Expected -is [pscustomobject]) {
        if ($Actual -isnot [pscustomobject]) { throw "Slim provenance changed: $Location" }
        $expectedProperties = @($Expected.PSObject.Properties)
        $actualProperties = @($Actual.PSObject.Properties)
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($property in $actualProperties) { $null = $names.Add($property.Name) }
        if ($expectedProperties.Count -ne $actualProperties.Count) { throw "Slim provenance changed: $Location" }
        foreach ($property in $expectedProperties) {
            if (-not $names.Contains($property.Name)) { throw "Slim provenance changed: $Location.$($property.Name)" }
            Assert-SlimInstallerJsonEqual $property.Value $Actual.PSObject.Properties[$property.Name].Value "$Location.$($property.Name)"
        }
        return
    }
    if ($Expected -is [Array]) {
        if ($Actual -isnot [Array] -or $Expected.Count -ne $Actual.Count) { throw "Slim provenance changed: $Location" }
        for ($index = 0; $index -lt $Expected.Count; $index++) {
            Assert-SlimInstallerJsonEqual $Expected[$index] $Actual[$index] "$Location[$index]"
        }
        return
    }
    if ($Actual -is [pscustomobject] -or $Actual -is [Array] -or
        (($Expected -is [string] -or $Actual -is [string] -or $Expected -is [bool] -or $Actual -is [bool]) -and
         $Expected.GetType() -ne $Actual.GetType()) -or $Expected -cne $Actual) {
        throw "Slim provenance changed: $Location"
    }
}

function Assert-SlimInstallerPayloadMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string] $PortableDirectory,
          [Parameter(Mandatory=$true)][string] $CoreDirectory)
    $portable = (Resolve-Path -LiteralPath $PortableDirectory).Path.TrimEnd('\', '/')
    $core = (Resolve-Path -LiteralPath $CoreDirectory).Path.TrimEnd('\', '/')
    foreach ($path in @($portable, $core)) {
        $parent = $path
        while ($parent) {
            if (((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Slim metadata cannot be verified through a link.'
            }
            $next = Split-Path -Parent $parent
            if ($next -eq $parent) { break }
            $parent = $next
        }
    }
    foreach ($item in Get-ChildItem -LiteralPath $core -Recurse -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Slim core contains a link.' }
    }
    $expected = Get-Content -LiteralPath (Join-Path $portable 'BUILD-PROVENANCE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($name in @('Ffmpeg', 'JapaneseReadings')) {
        if ($expected.PSObject.Properties.Name -cnotcontains $name -or
            $expected.$name.PSObject.Properties.Name -cnotcontains 'Bundled') {
            throw 'Portable provenance lacks optional-component metadata.'
        }
        $expected.$name.Bundled = $false
    }
    $expected | Add-Member -NotePropertyName InstallerPayload -NotePropertyValue 'core-only-v1' -Force
    $actual = Get-Content -LiteralPath (Join-Path $core 'BUILD-PROVENANCE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-SlimInstallerJsonEqual $expected $actual

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in Get-Content -LiteralPath (Join-Path $core 'SHA256SUMS') -Encoding UTF8) {
        if ($line -cnotmatch '^([0-9a-f]{64})  (.+)$') { throw 'Invalid slim core checksum record.' }
        $expectedHash = $Matches[1]
        $relative = $Matches[2]
        if ([IO.Path]::IsPathRooted($relative) -or $relative -match '[\\:*?"<>|\x00-\x1f]' -or
            $relative -match '(^|/)\.\.?(/|$)' -or $relative -match '(^/|//|/$)' -or
            $relative -ieq 'SHA256SUMS' -or -not $seen.Add($relative)) {
            throw 'Unsafe, duplicate or self-referential slim core checksum path.'
        }
        foreach ($part in ($relative -split '/')) {
            if ($part -match '[. ]$' -or $part -match '^(?i:con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\.|$)') {
                throw 'Ambiguous slim core checksum path.'
            }
        }
        $file = [IO.Path]::GetFullPath((Join-Path $core $relative))
        if (-not $file.StartsWith($core + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $file -PathType Leaf) -or
            (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $expectedHash) {
            throw "Slim core checksum mismatch: $relative"
        }
    }
    $files = @(Get-ChildItem -LiteralPath $core -Recurse -File -Force)
    if ($seen.Count -ne $files.Count - 1) { throw 'Slim core checksum coverage is incomplete.' }
    [pscustomobject]@{ ProvenanceVerified=$true; ChecksumFilesVerified=$seen.Count }
}
