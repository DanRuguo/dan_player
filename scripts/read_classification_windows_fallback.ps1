param([string]$MusicRoot = $env:DAN_PLAYER_CLASSIFICATION_ROOT)

# Machine-only, read-only stdout consumed by classification_readonly_probe.
# No settings/index are opened and no source files are modified.
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($MusicRoot)) { throw 'An explicitly authorized music root is required.' }
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$scriptDirectory = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Join-Path (Get-Location).Path 'scripts' } else { $PSScriptRoot }
$descriptorScript = Join-Path $scriptDirectory 'audit_classification_metadata.py'
$descriptors = python $descriptorScript $MusicRoot --descriptors | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Read-only metadata extraction failed.' }
$shellReader = New-Object -ComObject Shell.Application
$recoveredArtists = 0
$readFailures = 0
foreach ($descriptor in $descriptors) {
    if ($descriptor.artist -ne 'UNKNOWN' -or -not [string]::IsNullOrWhiteSpace($descriptor.composer)) { continue }
    try {
        $folder = $shellReader.Namespace([System.IO.Path]::GetDirectoryName($descriptor.path))
        $item = $folder.ParseName([System.IO.Path]::GetFileName($descriptor.path))
        $artists = @($item.ExtendedProperty('System.Music.Artist')) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        $composers = @($item.ExtendedProperty('System.Music.Composer')) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        if ($artists.Count -gt 0) {
            $descriptor.artist = $artists -join ' / '
            $recoveredArtists++
        }
        if ($composers.Count -gt 0) { $descriptor.composer = $composers -join ' / ' }
    } catch {
        $readFailures++
    }
}
[pscustomobject]@{
    descriptors = $descriptors
    windowsArtistRecoveries = $recoveredArtists
    windowsReadFailures = $readFailures
} | ConvertTo-Json -Depth 5 -Compress
