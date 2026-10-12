#requires -Version 5.1
function Test-OptionalPlayerComponentPath([string] $Relative) {
    return $Relative -match '^(?i:tools?)/(?:ffmpeg(?:-7\.1\.1)?|japanese_readings)/'
}

# Consume only entries whose original source bytes have already been audited.
# A separate core tree leaves the portable package unchanged and gives the
# installer its own truthful provenance/checksum manifest.
function New-SlimInstallerPayload {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)] $Entries,
          [Parameter(Mandatory=$true)][string] $Destination)
    if (Test-Path -LiteralPath $Destination) { throw 'Slim installer staging must be a new directory.' }
    $null = New-Item -ItemType Directory -Path $Destination
    foreach ($entry in $Entries) {
        if (Test-OptionalPlayerComponentPath $entry.Relative) { continue }
        if ($entry.Relative -in @('SHA256SUMS', 'BUILD-PROVENANCE.json')) { continue }
        $target = Join-Path $Destination $entry.Relative
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
        Copy-Item -LiteralPath $entry.Source -Destination $target
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine $entry.Hash) {
            throw "Slim installer staging changed source bytes: $($entry.Relative)"
        }
    }
    $provenanceEntry = @($Entries | Where-Object { $_.Relative -ceq 'BUILD-PROVENANCE.json' })
    if ($provenanceEntry.Count -gt 1) { throw 'Duplicate build provenance.' }
    if ($provenanceEntry.Count -eq 1) {
        $provenance = Get-Content -LiteralPath $provenanceEntry[0].Source -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($name in @('Ffmpeg', 'JapaneseReadings')) {
            if ($provenance.PSObject.Properties.Name -contains $name) { $provenance.$name.Bundled = $false }
        }
        $provenance | Add-Member -NotePropertyName InstallerPayload -NotePropertyValue 'core-only-v1' -Force
        [IO.File]::WriteAllText((Join-Path $Destination 'BUILD-PROVENANCE.json'),
            (($provenance | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
    }
    $prefix = $Destination.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $records = @(foreach ($file in Get-ChildItem -LiteralPath $Destination -Recurse -File | Sort-Object FullName) {
        $relative = $file.FullName.Substring($prefix.Length).Replace('\', '/')
        '{0}  {1}' -f (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $relative
    })
    [IO.File]::WriteAllText((Join-Path $Destination 'SHA256SUMS'), (($records -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    return $Destination
}
