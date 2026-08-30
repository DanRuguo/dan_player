#requires -Version 5.1
[CmdletBinding()]
param(
    [string] $ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string] $ReleaseDirectory,
    [string] $FlutterRoot = $env:FLUTTER_ROOT,
    [string] $ReportPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$fontRepository = Split-Path -Parent $PSScriptRoot
if (-not $ReleaseDirectory) { $ReleaseDirectory = Join-Path $ProjectRoot 'build\windows\x64\runner\Release' }
if (-not $FlutterRoot) {
    $localFlutter = Join-Path (Split-Path -Parent $fontRepository) 'tool\flutter'
    if (Test-Path -LiteralPath (Join-Path $localFlutter 'bin\cache\dart-sdk\bin\dart.exe') -PathType Leaf) {
        $FlutterRoot = $localFlutter
    } else {
        $flutterCommand = Get-Command flutter.bat -ErrorAction SilentlyContinue
        if ($flutterCommand) { $FlutterRoot = Split-Path -Parent (Split-Path -Parent $flutterCommand.Source) }
    }
}
if (-not $FlutterRoot) { throw 'Set FLUTTER_ROOT or pass -FlutterRoot for the release font audit.' }
$fontDart = Join-Path $FlutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
if (-not (Test-Path -LiteralPath $fontDart -PathType Leaf)) { throw "Dart SDK missing: $fontDart" }
$fontAuditScript = Join-Path $PSScriptRoot 'verify_release_fonts.dart'
# Resolve dependencies against the main project even when auditing the
# separately built desktop-lyrics bundle, without running pub or Flutter.
$fontPackageConfig = Join-Path $fontRepository '.dart_tool\package_config.json'
$fontArguments = @("--packages=$fontPackageConfig", $fontAuditScript, '--project-root', $ProjectRoot, '--release-dir', $ReleaseDirectory, '--flutter-root', $FlutterRoot)
if ($ReportPath) { $fontArguments += @('--report', $ReportPath) }
$fontOutput = & $fontDart @fontArguments
$fontExit = $LASTEXITCODE
foreach ($line in $fontOutput) { Write-Host $line }
if ($fontExit -ne 0) { throw "Release icon/font integrity gate failed (exit $fontExit)." }
