#requires -Version 5.1
# The contextual IPADIC dictionary stays separate from the Rust DLL. Pinned
# supplemental lexical/character readings stay in the same optional component.
function Get-BundledJapaneseReadings {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string] $RepositoryRoot)
    $readingRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
    $readingCatalog = Get-Content -LiteralPath (Join-Path $readingRoot 'scripts\support\bundled_japanese_readings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($readingCatalog.schemaVersion -ne 1 -or
        $readingCatalog.resource.path -cne 'rust/assets/ipadic-reading.bin.gz' -or
        $readingCatalog.resource.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $readingCatalog.resource.bytes -le 0 -or @($readingCatalog.notices).Count -ne 4 -or
        @($readingCatalog.supplements).Count -ne 2) {
        throw 'Invalid bundled Japanese reading catalog.'
    }
    $readingResource = Join-Path $readingRoot $readingCatalog.resource.path
    if ((Get-Item -LiteralPath $readingResource).Length -ne $readingCatalog.resource.bytes -or
        (Get-FileHash -LiteralPath $readingResource -Algorithm SHA256).Hash.ToLowerInvariant() -cne $readingCatalog.resource.sha256) {
        throw 'Japanese reading resource differs from its pinned derivation.'
    }
    $readingSupplements = @()
    $readingSupplementPaths = @('rust/assets/supplemental-reading-v1.json.gz', 'rust/assets/kanji-reading-v1.json.gz')
    foreach ($readingSupplement in $readingCatalog.supplements) {
        if ($readingSupplement.path -cnotin $readingSupplementPaths -or
            $readingSupplement.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
            $readingSupplement.embedded -ne $false -or $readingSupplement.entries -le 0) {
            throw 'Invalid supplemental Japanese reading resource.'
        }
        $readingSupplementPaths = @($readingSupplementPaths | Where-Object { $_ -cne $readingSupplement.path })
        $readingSupplementFile = Join-Path $readingRoot $readingSupplement.path
        if ((Get-Item -LiteralPath $readingSupplementFile).Length -ne $readingSupplement.bytes -or
            (Get-FileHash -LiteralPath $readingSupplementFile).Hash.ToLowerInvariant() -cne $readingSupplement.sha256) {
            throw 'Supplemental Japanese reading data differs from its pinned derivation.'
        }
        $readingSupplements += $readingSupplement
    }
    if ($readingSupplementPaths.Count -ne 0) { throw 'Incomplete supplemental Japanese readings.' }
    $readingNotices = @()
    $readingSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($readingNotice in $readingCatalog.notices) {
        if ($readingNotice.path -cnotmatch '^licenses/(?:LINDERA|IPADIC|EDRDG)/[A-Za-z][A-Za-z0-9._-]*$' -or
            $readingNotice.sha256 -cnotmatch '^[0-9a-f]{64}$' -or -not $readingSeen.Add($readingNotice.path)) {
            throw 'Unsafe, duplicate or unpinned Japanese reading notice.'
        }
        $readingSource = Join-Path $readingRoot $readingNotice.path
        $readingHash = (Get-FileHash -LiteralPath $readingSource -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($readingHash -cne $readingNotice.sha256) {
            throw "Japanese reading notice differs from its pinned original: $($readingNotice.path)"
        }
        $readingNotices += [pscustomobject]@{ RelativePath=$readingNotice.path; SourcePath=$readingSource; Sha256=$readingHash }
    }
    foreach ($readingProvenance in @('licenses/IPADIC/PROVENANCE.md', 'licenses/EDRDG/PROVENANCE.md')) {
        $readingNotices += [pscustomobject]@{
            RelativePath=$readingProvenance; SourcePath=(Join-Path $readingRoot $readingProvenance)
            Sha256=(Get-FileHash -LiteralPath (Join-Path $readingRoot $readingProvenance) -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    [pscustomobject]@{
        Engine=$readingCatalog.engine; DictionaryBytes=$readingCatalog.resource.bytes
        DictionarySha256=$readingCatalog.resource.sha256; Optional=$true; Bundled=$false
        Notices=$readingNotices; Supplements=$readingSupplements
    }
}
