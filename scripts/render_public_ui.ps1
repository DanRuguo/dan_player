param(
    [string]$Flutter = '',
    [switch]$VerifyOnly,
    [string]$TestFile = 'test/public_ui_showcase_test.dart',
    [string]$TestName,
    [ValidateSet('', 'library', 'settings', 'playlists', 'categories', 'mini', 'desktop', 'appearance', 'theme', 'search', 'folders', 'statistics', 'playerbar', 'songpicker', 'spectrum')]
    [string]$Page = '',
    [string]$OutputDirectory,
    [switch]$PlanOnly
)
$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testPath = [IO.Path]::GetFullPath((Join-Path $repoRoot $TestFile))
if (-not $testPath.StartsWith((Join-Path $repoRoot 'test') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
    -not $testPath.EndsWith('_test.dart') -or -not (Test-Path -LiteralPath $testPath -PathType Leaf)) { throw 'Choose an existing repository test/*_test.dart fixture.' }
if ($Page -and $TestFile.Replace('\', '/') -ne 'test/public_ui_showcase_test.dart') { throw '-Page selects public_ui_showcase pages; use -TestName for another fixture.' }
if ($OutputDirectory) {
    $OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
    $workspace = [IO.Path]::GetFullPath((Join-Path $repoRoot '..')).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $OutputDirectory.StartsWith($workspace, [StringComparison]::OrdinalIgnoreCase)) { throw 'Render output must stay inside the development workspace.' }
}
if (-not $VerifyOnly -and $TestFile.Replace('\', '/') -ne 'test/public_ui_showcase_test.dart' -and -not $OutputDirectory) {
    throw 'A focused fixture export requires -OutputDirectory; use -VerifyOnly for layout checks.'
}
if ([string]::IsNullOrWhiteSpace($Flutter)) {
    $bundledFlutter = Join-Path $repoRoot '..\tool\flutter\bin\flutter.bat'
    $Flutter = if (Test-Path -LiteralPath $bundledFlutter) { $bundledFlutter } else { 'flutter' }
}
Push-Location $repoRoot
try {
    $renderArguments = @('test', '--no-pub', '--reporter', 'expanded')
    if (-not $VerifyOnly) {
        $renderArguments += '--dart-define=DAN_PLAYER_EXPORT_PUBLIC_UI=true'
        if ($OutputDirectory) { $renderArguments += "--dart-define=DAN_PLAYER_UPDATE_RENDER_DIR=$OutputDirectory" }
    }
    if ($Page) { $renderArguments += "--dart-define=DAN_PLAYER_PUBLIC_UI_PAGE=$Page" }
    if ($TestName) { $renderArguments += @('--plain-name', $TestName) }
    $renderArguments += $TestFile
    if ($PlanOnly) { return [pscustomobject]@{ Flutter=$Flutter; Arguments=$renderArguments; VerifyOnly=[bool]$VerifyOnly } }
    & $Flutter @renderArguments
    if ($LASTEXITCODE -ne 0) { throw 'Public UI widget rendering failed.' }
} finally {
    Pop-Location
}
