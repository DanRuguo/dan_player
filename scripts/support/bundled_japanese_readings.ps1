#requires -Version 5.1
# The dictionary stays separate from the Rust DLL and is hash pinned. Full
# portable packages include it; slim installers preserve existing components.
function Get-BundledJapaneseReadings {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string] $RepositoryRoot)
    $readingRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
    $readingCatalog = Get-Content -LiteralPath (Join-Path $readingRoot 'scripts\support\bundled_japanese_readings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($readingCatalog.schemaVersion -ne 1 -or
        $readingCatalog.resource.path -cne 'rust/assets/ipadic-reading.bin.gz' -or
        $readingCatalog.resource.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $readingCatalog.resource.bytes -le 0 -or @($readingCatalog.notices).Count -ne 2) {
        throw 'Invalid bundled Japanese reading catalog.'
    }
    $readingResource = Join-Path $readingRoot $readingCatalog.resource.path
    if ((Get-Item -LiteralPath $readingResource).Length -ne $readingCatalog.resource.bytes -or
        (Get-FileHash -LiteralPath $readingResource -Algorithm SHA256).Hash.ToLowerInvariant() -cne $readingCatalog.resource.sha256) {
        throw 'Japanese reading resource differs from its pinned derivation.'
    }
    $readingNotices = @()
    $readingSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($readingNotice in $readingCatalog.notices) {
        if ($readingNotice.path -cnotmatch '^licenses/(?:LINDERA|IPADIC)/[A-Za-z][A-Za-z0-9._-]*$' -or
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
    $readingProvenance = 'licenses/IPADIC/PROVENANCE.md'
    $readingNotices += [pscustomobject]@{
        RelativePath=$readingProvenance; SourcePath=(Join-Path $readingRoot $readingProvenance)
        Sha256=(Get-FileHash -LiteralPath (Join-Path $readingRoot $readingProvenance) -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    [pscustomobject]@{
        Engine=$readingCatalog.engine; DictionaryBytes=$readingCatalog.resource.bytes
        DictionarySha256=$readingCatalog.resource.sha256; Optional=$true; Bundled=$false
        Notices=$readingNotices
    }
}
