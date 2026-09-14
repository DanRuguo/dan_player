[CmdletBinding()]
param([string] $CacheRoot, [string] $Destination, [switch] $VerifyOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repository = Split-Path -Parent $PSScriptRoot
if (-not $CacheRoot) { $CacheRoot = Join-Path (Split-Path -Parent $repository) 'tool/ffmpeg-7.1.1/runtime' }
$manifestPath = Join-Path $PSScriptRoot 'ffmpeg_runtime_manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $CacheRoot -PathType Container)) {
    throw 'The pinned FFmpeg runtime is missing. Populate tool/ffmpeg-7.1.1/runtime from the matching Gyan distribution before packaging.'
}
function Assert-RegularFile([string] $FilePath) {
    $item = Get-Item -LiteralPath $FilePath -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Invalid runtime file: $FilePath" }
}
foreach ($entry in $manifest.Files) {
    if ([IO.Path]::GetFileName($entry.Name) -cne $entry.Name) { throw 'Invalid manifest name' }
    $source = Join-Path $CacheRoot $entry.Name
    Assert-RegularFile $source
    if ((Get-Item -LiteralPath $source).Length -ne $entry.Size -or
        (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ine $entry.Sha256) { throw "FFmpeg integrity mismatch: $($entry.Name)" }
}
if (-not $VerifyOnly) {
    if (-not $Destination) { throw 'Destination is required when staging FFmpeg' }
    $null = New-Item -ItemType Directory -Path $Destination -Force
    if ((Get-Item -LiteralPath $Destination).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Runtime destination must not be a link' }
    foreach ($entry in $manifest.Files) {
        $target = Join-Path $Destination $entry.Name
        if (Test-Path -LiteralPath $target) { Assert-RegularFile $target }
        Copy-Item -LiteralPath (Join-Path $CacheRoot $entry.Name) -Destination $target
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine $entry.Sha256) { throw "Staged FFmpeg mismatch: $($entry.Name)" }
    }
}
[pscustomobject]@{ Version=$manifest.Version; Source=$manifest.Source; License=$manifest.License; RuntimeDirectory=(Resolve-Path -LiteralPath $CacheRoot).Path; Files=$manifest.Files; ManifestSha256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash }
