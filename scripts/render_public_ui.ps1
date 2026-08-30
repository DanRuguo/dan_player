param(
    [string]$Flutter = '',
    [switch]$VerifyOnly
)
$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($Flutter)) {
    $bundledFlutter = Join-Path $repoRoot '..\tool\flutter\bin\flutter.bat'
    $Flutter = if (Test-Path -LiteralPath $bundledFlutter) { $bundledFlutter } else { 'flutter' }
}
Push-Location $repoRoot
try {
    $renderArguments = @('test', '--no-pub', '--reporter', 'expanded')
    if (-not $VerifyOnly) {
        $renderArguments += '--dart-define=DAN_PLAYER_EXPORT_PUBLIC_UI=true'
    }
    $renderArguments += 'test/public_ui_showcase_test.dart'
    & $Flutter @renderArguments
    if ($LASTEXITCODE -ne 0) { throw 'Public UI widget rendering failed.' }
} finally {
    Pop-Location
}
