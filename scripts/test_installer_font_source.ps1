#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repository = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'support\bundled_fonts.ps1')
$font = Get-BundledInstallerFont -RepositoryRoot $repository
$runtimeSource = Join-Path $repository 'build\runtime-font-copy.ttf'
$arguments = @{ RelativePath=$font.PayloadRelativePath; SourcePath=$runtimeSource; Sha256=$font.Sha256; Bytes=$font.Bytes; InstallerFont=$font }
if ((Get-InstallerPayloadSource @arguments) -cne $font.SourcePath) { throw 'Pinned runtime font must share the private wizard source.' }
foreach ($relative in @('assets/fonts/PingFangSC-Regular.ttf', 'data/flutter_assets/assets/fonts/PingFangSC-Regular.ttf', 'data/flutter_assets/packages/desktop_lyric/assets/fonts/GoogleSans-VF.ttf')) {
    $arguments.RelativePath = $relative
    if ((Get-InstallerPayloadSource @arguments) -cne $runtimeSource) { throw "Unrelated payload source changed: $relative" }
}
$arguments.RelativePath = $font.PayloadRelativePath.ToUpperInvariant()
if ((Get-InstallerPayloadSource @arguments) -cne $font.SourcePath) { throw 'Windows path case must not duplicate the pinned font.' }
$arguments.RelativePath = $font.PayloadRelativePath
foreach ($change in @('hash', 'length')) {
    $arguments.Sha256 = $font.Sha256
    $arguments.Bytes = $font.Bytes
    if ($change -eq 'hash') { $arguments.Sha256 = '0' * 64 } else { $arguments.Bytes++ }
    $rejected = $false
    try { $null = Get-InstallerPayloadSource @arguments } catch {
        if ($_.Exception.Message -ne 'Runtime installer font differs from its pinned original.') { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw "Changed runtime font $change must fail before compression." }
}
Write-Output 'PASS: shared source, three unrelated destinations, Windows case, changed hash and length (7 cases).'
