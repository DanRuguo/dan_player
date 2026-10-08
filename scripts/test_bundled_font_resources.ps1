#requires -Version 5.1
[CmdletBinding()]
param([string] $OutputDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'support\bundled_fonts.ps1')
$fontRepository = Split-Path -Parent $PSScriptRoot
$fontQaParent = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $fontRepository) 'tool\qa-local')).TrimEnd('\', '/')
$fontQa = if ($OutputDirectory) { [IO.Path]::GetFullPath($OutputDirectory) } else { Join-Path $fontQaParent 'font-resources' }
if (-not $fontQa.StartsWith($fontQaParent + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Font policy fixtures must remain in workspace QA.' }
$fontAncestor = $fontQa
while ($fontAncestor) {
    if ((Test-Path -LiteralPath $fontAncestor) -and
        ((Get-Item -LiteralPath $fontAncestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Refusing a QA reparse point.' }
    $fontNext = Split-Path -Parent $fontAncestor
    if ($fontNext -eq $fontAncestor) { break }
    $fontAncestor = $fontNext
}
$fontCases = 0
function Assert-FontContract([bool] $Condition, [string] $Name) {
    if (-not $Condition) { throw $Name }
    $script:fontCases++
    Write-Output "PASS $Name"
}
function Assert-FontRejected([scriptblock] $Action, [string] $Name) {
    $fontRejected = $false
    try { & $Action | Out-Null } catch { $fontRejected = $true }
    Assert-FontContract $fontRejected $Name
}
$fontNotices = @(Get-BundledFontNotices -RepositoryRoot $fontRepository)
$fontInstaller = Get-BundledInstallerFont -RepositoryRoot $fontRepository
Assert-FontContract ($fontNotices.Count -eq 10 -and $fontInstaller.Bytes -eq 16529832 -and
    $fontInstaller.Sha256 -ceq 'f1d8611151880c6c336aabeac4640ef434fa13cbfbf1ffe82d0a71b2a5637256') 'original 10 notices and shared full SC font are pinned'
$fontFixture = Join-Path $fontQa ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fontFixture 'scripts\support') -Force | Out-Null
$fontCatalogPath = Join-Path $fontFixture 'scripts\support\bundled_fonts.json'
$fontCatalogText = [IO.File]::ReadAllText((Join-Path $fontRepository 'scripts\support\bundled_fonts.json'))
function Reset-FontCatalog {
    [IO.File]::WriteAllText($fontCatalogPath, $fontCatalogText, [Text.UTF8Encoding]::new($false))
}
function Write-FontCatalog($Value) {
    [IO.File]::WriteAllText($fontCatalogPath, ($Value | ConvertTo-Json -Depth 15), [Text.UTF8Encoding]::new($false))
}
try {
    Reset-FontCatalog
    $fontCatalog = $fontCatalogText | ConvertFrom-Json
    foreach ($fontLicense in $fontCatalog.licenses) {
        $fontSource = Join-Path $fontRepository $fontLicense.directory
        $fontTarget = Join-Path $fontFixture $fontLicense.directory
        New-Item -ItemType Directory -Path $fontTarget -Force | Out-Null
        foreach ($fontNotice in $fontLicense.files) {
            Copy-Item -LiteralPath (Join-Path $fontSource $fontNotice.name) -Destination (Join-Path $fontTarget $fontNotice.name)
        }
    }
    $fontFixtureFile = Join-Path $fontFixture $fontInstaller.RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $fontFixtureFile) -Force | Out-Null
    Copy-Item -LiteralPath $fontInstaller.SourcePath -Destination $fontFixtureFile
    Assert-FontContract (@(Get-BundledFontNotices $fontFixture).Count -eq 10 -and
        (Get-BundledInstallerFont $fontFixture).Sha256 -ceq $fontInstaller.Sha256) 'isolated source copies preserve original notice and font bytes'

    $fontNoticeFile = Join-Path $fontFixture $fontNotices[0].RelativePath
    $fontNoticeBytes = [IO.File]::ReadAllBytes($fontNoticeFile)
    [IO.File]::WriteAllText($fontNoticeFile, 'changed license')
    Assert-FontRejected { Get-BundledFontNotices $fontFixture } 'changed upstream license bytes are rejected'
    [IO.File]::WriteAllBytes($fontNoticeFile, $fontNoticeBytes)

    $fontCatalog = $fontCatalogText | ConvertFrom-Json
    $fontCatalog.licenses[0].directory = 'licenses/../outside'
    Write-FontCatalog $fontCatalog
    Assert-FontRejected { Get-BundledFontNotices $fontFixture } 'traversal notice directory is rejected'
    Reset-FontCatalog

    $fontCatalog = $fontCatalogText | ConvertFrom-Json
    $fontCatalog.licenses += $fontCatalog.licenses[0]
    Write-FontCatalog $fontCatalog
    Assert-FontRejected { Get-BundledFontNotices $fontFixture } 'duplicate notice ownership is rejected'
    Reset-FontCatalog

    $fontCatalog = $fontCatalogText | ConvertFrom-Json
    $fontCatalog.licenses[0].files[0].sha256 = ('0' * 64)
    Write-FontCatalog $fontCatalog
    Assert-FontRejected { Get-BundledFontNotices $fontFixture } 'wrong original notice hash is rejected'
    Reset-FontCatalog

    Remove-Item -LiteralPath $fontNoticeFile
    Assert-FontRejected { Get-BundledFontNotices $fontFixture } 'missing original notice file is rejected'
    [IO.File]::WriteAllBytes($fontNoticeFile, $fontNoticeBytes)

    $fontCatalog = $fontCatalogText | ConvertFrom-Json
    $fontCatalog.fonts[0].source = 'assets/fonts/PingFangSC-Regular.ttf'
    Write-FontCatalog $fontCatalog
    Assert-FontRejected { Get-BundledInstallerFont $fontFixture } 'installer cannot regress to the deleted main font copy'
    Reset-FontCatalog

    $fontCatalog = $fontCatalogText | ConvertFrom-Json
    $fontCatalog.fonts += $fontCatalog.fonts[0]
    Write-FontCatalog $fontCatalog
    Assert-FontRejected { Get-BundledInstallerFont $fontFixture } 'ambiguous installer SC font ownership is rejected'
    Reset-FontCatalog

    $fontCatalog = $fontCatalogText | ConvertFrom-Json
    $fontCatalog.fonts[0].bytes++
    Write-FontCatalog $fontCatalog
    Assert-FontRejected { Get-BundledInstallerFont $fontFixture } 'installer original font length mismatch is rejected'
    Reset-FontCatalog

    $fontBytes = [IO.File]::ReadAllBytes($fontFixtureFile)
    $fontBytes[0] = $fontBytes[0] -bxor 1
    [IO.File]::WriteAllBytes($fontFixtureFile, $fontBytes)
    Assert-FontRejected { Get-BundledInstallerFont $fontFixture } 'same length damaged installer font bytes are rejected'
    $fontBytes[0] = $fontBytes[0] -bxor 1
    [IO.File]::WriteAllBytes($fontFixtureFile, $fontBytes)

    $fontCatalog = $fontCatalogText | ConvertFrom-Json
    $fontCatalog.schemaVersion = 2
    Write-FontCatalog $fontCatalog
    Assert-FontRejected { Get-BundledInstallerFont $fontFixture } 'unknown font catalog schema is rejected'
    Write-Output "RESULT $fontCases font resource policy cases passed; no build or installation"
} finally {
    $fontResolvedFixture = (Resolve-Path -LiteralPath $fontFixture).Path
    if (-not $fontResolvedFixture.StartsWith($fontQa + '\', [StringComparison]::OrdinalIgnoreCase) -or
        ((Get-Item -LiteralPath $fontResolvedFixture -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Refusing cleanup outside the isolated font QA fixture.' }
    Remove-Item -LiteralPath $fontResolvedFixture -Recurse -Force
}
