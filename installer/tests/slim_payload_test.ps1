#requires -Version 5.1
param([Parameter(Mandatory=$true)][string] $QaDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'scripts\support\slim_installer_payload.ps1')
. (Join-Path $repo 'scripts\support\slim_installer_verification.ps1')
$base = [IO.Path]::GetFullPath($QaDirectory)
$workspace = Split-Path -Parent $repo
if (-not $base.StartsWith((Join-Path $workspace 'tool\qa-local\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture must stay inside workspace QA.' }
$run = Join-Path $base ('slim-payload-' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $run 'portable'
$destination = Join-Path $run 'installer-core'
$null = New-Item -ItemType Directory -Path $source -Force
$files = [ordered]@{
    'Dan Player.exe'='synthetic player'
    'data/app.so'='synthetic kernel'
    'LICENSE'='synthetic license'
    'tool/ffmpeg/ffmpeg.exe'='optional ffmpeg'
    'tools/ffmpeg/README.txt'='optional legacy ffmpeg'
    'tool/japanese_readings/ipadic-reading.bin.gz'='optional dictionary'
    'tools/japanese_readings/licenses/IPADIC/NOTICE.txt'='optional dictionary notice'
    'SHA256SUMS'='original portable manifest'
    'BUILD-PROVENANCE.json'='{"Product":"Dan Player","Version":"26.1.1","SourceRevision":"0123456789abcdef0123456789abcdef01234567","FontResources":[{"Family":"Source Han Sans SC","Sha256":"font-source-hash"}],"Ffmpeg":{"Optional":true,"Bundled":true},"JapaneseReadings":{"Optional":true,"Bundled":true,"DictionarySha256":"dictionary-source-hash"}}'
}
$entries = @(foreach ($entry in $files.GetEnumerator()) {
    $file = Join-Path $source $entry.Key
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force
    [IO.File]::WriteAllText($file, $entry.Value, [Text.UTF8Encoding]::new($false))
    [pscustomobject]@{ Relative=$entry.Key; Source=$file; Hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant(); Length=(Get-Item -LiteralPath $file).Length }
})
$null = New-SlimInstallerPayload -Entries $entries -Destination $destination
foreach ($entry in $entries) {
    if ((Get-FileHash -LiteralPath $entry.Source -Algorithm SHA256).Hash -cne $entry.Hash.ToUpperInvariant()) { throw 'Portable source was changed.' }
    $target = Join-Path $destination $entry.Relative
    if (Test-OptionalPlayerComponentPath $entry.Relative) {
        if (Test-Path -LiteralPath $target) { throw 'Optional component entered the slim installer.' }
    } elseif ($entry.Relative -notin @('SHA256SUMS', 'BUILD-PROVENANCE.json') -and
        (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne $entry.Hash.ToUpperInvariant()) { throw 'Core bytes changed.' }
}
$provenance = Get-Content -LiteralPath (Join-Path $destination 'BUILD-PROVENANCE.json') -Raw | ConvertFrom-Json
if ($provenance.Ffmpeg.Bundled -or $provenance.JapaneseReadings.Bundled -or $provenance.InstallerPayload -cne 'core-only-v1') { throw 'Slim provenance still claims bundled components.' }
$records = @(Get-Content -LiteralPath (Join-Path $destination 'SHA256SUMS'))
if ($records.Count -ne 4) { throw 'Core manifest coverage changed.' }
foreach ($line in $records) {
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { throw 'Malformed core checksum.' }
    if ((Get-FileHash -LiteralPath (Join-Path $destination $Matches[2]) -Algorithm SHA256).Hash -ine $Matches[1]) { throw 'Core checksum mismatch.' }
}
Write-Output 'PASS full portable retained, optional components excluded, core hashes and provenance verified'

$metadata = Assert-SlimInstallerPayloadMetadata -PortableDirectory $source -CoreDirectory $destination
if (-not $metadata.ProvenanceVerified -or $metadata.ChecksumFilesVerified -ne 4) { throw 'Valid independent metadata verification failed.' }
Write-Output 'PASS independent core provenance and checksum coverage'

# Every damaged fixture also receives a valid runtime manifest. Independent
# metadata checks must reject it even when its packaged bytes are self-consistent.
function Write-SelfConsistentRuntimeManifest([string] $Core, [string] $Name) {
    $prefix = $Core.TrimEnd('\', '/') + '\'
    $lines = @(foreach ($file in Get-ChildItem -LiteralPath $Core -Recurse -File -Force | Sort-Object FullName) {
        $relative = $file.FullName.Substring($prefix.Length).Replace('\', '/')
        '{0}{1}{2}{1}{3}' -f (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), "`t", $file.Length, $relative
    })
    $manifest = Join-Path $run ($Name + '.manifest')
    [IO.File]::WriteAllText($manifest, ("DANPLAYER_PAYLOAD_V1`n26.1.1`n" + ($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    foreach ($line in (Get-Content -LiteralPath $manifest | Select-Object -Skip 2)) {
        $fields = $line -split "`t"
        $file = Join-Path $Core $fields[2]
        if ($fields.Count -ne 3 -or (Get-Item -LiteralPath $file).Length -ne [long]$fields[1] -or
            (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $fields[0]) { throw 'Synthetic runtime manifest is not self-consistent.' }
    }
}

function Write-CoreChecksums([string] $Core) {
    $prefix = $Core.TrimEnd('\', '/') + '\'
    $lines = @(foreach ($file in Get-ChildItem -LiteralPath $Core -Recurse -File -Force | Where-Object Name -ne 'SHA256SUMS' | Sort-Object FullName) {
        '{0}  {1}' -f (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $file.FullName.Substring($prefix.Length).Replace('\', '/')
    })
    [IO.File]::WriteAllText((Join-Path $Core 'SHA256SUMS'), (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
}

$rejections = 0
foreach ($defect in @('source-revision', 'font-source', 'dictionary-source', 'bundled', 'payload-kind', 'extra-property', 'removed-property',
                     'checksum-missing', 'checksum-duplicate', 'checksum-hash', 'checksum-traversal', 'checksum-self')) {
    $damaged = Join-Path $run ('core-' + $defect)
    $null = New-SlimInstallerPayload -Entries $entries -Destination $damaged
    $provenancePath = Join-Path $damaged 'BUILD-PROVENANCE.json'
    $value = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
    switch ($defect) {
        'source-revision' { $value.SourceRevision = 'ffffffffffffffffffffffffffffffffffffffff' }
        'font-source' { $value.FontResources[0].Sha256 = 'changed-font-source' }
        'dictionary-source' { $value.JapaneseReadings.DictionarySha256 = 'changed-dictionary-source' }
        'bundled' { $value.Ffmpeg.Bundled = $true }
        'payload-kind' { $value.InstallerPayload = 'full-portable-v1' }
        'extra-property' { $value | Add-Member -NotePropertyName Unexpected -NotePropertyValue $true }
        'removed-property' { $value.PSObject.Properties.Remove('SourceRevision') }
    }
    [IO.File]::WriteAllText($provenancePath, (($value | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
    Write-CoreChecksums $damaged
    $checksumPath = Join-Path $damaged 'SHA256SUMS'
    $checksums = @(Get-Content -LiteralPath $checksumPath)
    switch ($defect) {
        'checksum-missing' { $checksums = @($checksums | Select-Object -Skip 1) }
        'checksum-duplicate' { $checksums += $checksums[0] }
        'checksum-hash' { $checksums[0] = ('0' * 64) + $checksums[0].Substring(64) }
        'checksum-traversal' { $checksums[0] = $checksums[0].Substring(0, 66) + 'data/../Dan Player.exe' }
        'checksum-self' { $checksums += ('0' * 64) + '  SHA256SUMS' }
    }
    [IO.File]::WriteAllText($checksumPath, (($checksums -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    Write-SelfConsistentRuntimeManifest $damaged $defect
    $rejected = $false
    try { $null = Assert-SlimInstallerPayloadMetadata -PortableDirectory $source -CoreDirectory $damaged }
    catch { $rejected = $true }
    if (-not $rejected) { throw "Independent verifier accepted damaged metadata: $defect" }
    $rejections++
    Write-Output "PASS independent rejection of $defect with a self-consistent runtime manifest"
}
if ($rejections -ne 12) { throw 'Independent rejection coverage changed.' }
