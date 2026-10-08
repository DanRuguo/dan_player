#requires -Version 5.1
# Read-only original font notices. Both assembly and independent verification
# consume the same pinned catalog; no filename whitelist is duplicated here.
function Get-BundledFontNotices {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string] $RepositoryRoot)
    $fontRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
    $fontCatalog = Get-Content -LiteralPath (Join-Path $fontRoot 'scripts\support\bundled_fonts.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($fontCatalog.schemaVersion -ne 1 -or $fontCatalog.ownerPackage -cne 'desktop_lyric' -or
        $fontCatalog.ownerDirectory -cne 'third_party/desktop_lyric' -or @($fontCatalog.fonts).Count -ne 4) {
        throw 'Invalid shared bundled font catalog.'
    }
    $fontSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($fontLicense in $fontCatalog.licenses) {
        if ($fontLicense.directory -cnotmatch '^licenses/[A-Z][A-Z-]+$') { throw 'Unsafe font license directory.' }
        foreach ($fontNotice in $fontLicense.files) {
            if ($fontNotice.name -cnotmatch '^[A-Za-z][A-Za-z0-9._-]+$' -or
                $fontNotice.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Unsafe/unpinned font notice.' }
            $fontRelative = $fontLicense.directory + '/' + $fontNotice.name
            if (-not $fontSeen.Add($fontRelative)) { throw 'Duplicate font notice.' }
            $fontSource = Join-Path $fontRoot $fontRelative
            $fontActual = (Get-FileHash -LiteralPath $fontSource -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($fontActual -cne $fontNotice.sha256) { throw "Font notice differs from pinned original: $fontRelative" }
            [pscustomobject]@{ RelativePath=$fontRelative; SourcePath=$fontSource; Sha256=$fontActual }
        }
    }
    if ($fontSeen.Count -lt 9) { throw 'Incomplete original font license notices.' }
}

function Get-BundledInstallerFont {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string] $RepositoryRoot)
    $fontRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
    $fontCatalog = Get-Content -LiteralPath (Join-Path $fontRoot 'scripts\support\bundled_fonts.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $fontChoices = @($fontCatalog.fonts | Where-Object { $_.family -ceq 'DanPingFangSC' })
    if ($fontCatalog.schemaVersion -ne 1 -or $fontChoices.Count -ne 1 -or
        $fontChoices[0].source -cne 'third_party/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf') {
        throw 'Installer must use the authoritative shared SC font.'
    }
    $fontChoice = $fontChoices[0]
    $fontSource = Join-Path $fontRoot $fontChoice.source
    $fontHash = (Get-FileHash -LiteralPath $fontSource -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-Item -LiteralPath $fontSource).Length -ne $fontChoice.bytes -or $fontHash -cne $fontChoice.sha256) {
        throw 'Installer font differs from its pinned original.'
    }
    [pscustomobject]@{ SourcePath=$fontSource; RelativePath=$fontChoice.source; Sha256=$fontHash; Bytes=$fontChoice.bytes }
}
