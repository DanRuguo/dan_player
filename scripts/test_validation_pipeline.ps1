[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'support/validation_receipt.ps1')
. (Join-Path $PSScriptRoot 'support/ci_impact.ps1')
. (Join-Path $PSScriptRoot 'support/signature_integrity.ps1')
$repo = Split-Path -Parent $PSScriptRoot
$checks = 0
function Assert-Policy([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}

$documents = Get-WindowsCiImpact $repo @('README.md', 'docs/release-26.0.5-snapshot.2.md')
Assert-Policy ($documents.Profile -eq 'documents') 'Documents must still have a lightweight successful check path.'
$business = Get-WindowsCiImpact $repo @('test/queue_undo_test.dart')
Assert-Policy ($business.Profile -eq 'business' -and 'test/queue_undo_test.dart' -cin $business.Tests) 'Dart fixture changes must retain their affected test.'
$business = Get-WindowsCiImpact $repo @('lib/play_service/queue_edits.dart')
Assert-Policy ($business.Profile -eq 'business' -and 'test/queue_undo_test.dart' -cin $business.Tests -and 'test/current_playlist_view_test.dart' -cin $business.Tests) 'Production business changes must follow actual dependent tests.'
foreach ($path in @('lib/main.dart', 'lib/play_service/playback_service.dart', 'lib/src/rust/frb_generated.dart', 'lib/update/update_service.dart', 'lib/page/updating_page.dart', 'windows/runner/main.cpp', 'third_party/desktop_lyric/lib/main.dart', 'assets/fonts/PingFangSC-Regular.ttf', 'pubspec.lock', 'scripts/build_windows_release.ps1', 'new-unknown-input')) {
    Assert-Policy ((Get-WindowsCiImpact $repo @($path)).Profile -eq 'integration') "Shared/unknown input was under-tested: $path"
}
Assert-Policy ((Get-WindowsCiImpact $repo @('README.md') -ForceIntegration).Profile -eq 'integration') 'Explicit release/integration dispatch must never take the documentation shortcut.'

$inputs = [pscustomobject]@{ Hash='source-and-lock-content'; Revision='first'; Worktree=@() }
$tools = [pscustomobject]@{ Hash='compiler-toolchain' }
$receipt = [pscustomobject]@{ Schema=1; Passed=$true; Inputs=$inputs; Toolchain=$tools; Tests=@('a', 'b') }
Assert-Policy (Test-ValidationReceipt $receipt $inputs $tools @('a')) 'A verified superset must cover its unchanged subset.'
Assert-Policy (-not (Test-ValidationReceipt $receipt $inputs $tools @('c'))) 'Uncovered tests cannot reuse a prior result.'
Assert-Policy (-not (Test-ValidationReceipt $receipt ([pscustomobject]@{Hash='changed-source'}) $tools @('a'))) 'Source/lock changes must invalidate receipts.'
Assert-Policy (-not (Test-ValidationReceipt $receipt $inputs ([pscustomobject]@{Hash='changed-toolchain'}) @('a'))) 'Toolchain changes must invalidate receipts.'
Assert-Policy (-not (Test-ValidationReceipt $null $inputs $tools @('a'))) 'A missing receipt cannot bypass tests.'
Assert-Policy (-not (Test-ValidationReceipt ([pscustomobject]@{Schema=1}) $inputs $tools @('a'))) 'A malformed receipt cannot bypass tests.'

$temporary = Join-Path $repo ('tool/qa-validation-pipeline/' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporary -Force
try {
    $file = Join-Path $temporary 'artifact.bin'
    [IO.File]::WriteAllText($file, 'first exact payload')
    $unsigned = Get-AuthenticodeIntegrity $file 'expected' $false
    Assert-Policy (-not $unsigned.Accepted) 'An unsigned file must fail integrity before receipt matching.'
    $unsignedTrust = [DanPlayerReleaseTrust]::Verify($file)
    Assert-Policy ($unsignedTrust -ne 0 -and $unsignedTrust.ToString('X8') -ne '800B0109') 'WinVerifyTrust must reject an unsigned payload, not mistake it for a self-signed chain.'
    $records = @(Get-ArtifactContentRecords $temporary)
    $build = [pscustomobject]@{ Schema=1; Passed=$true; Inputs=$inputs; Toolchain=$tools; Tests=@(); ArtifactHash=Get-TextSha256 ($records | ConvertTo-Json -Compress) }
    Assert-Policy (Test-ArtifactReceipt $build $inputs $tools $records) 'Identical complete payload must reuse its build result.'
    [IO.File]::WriteAllText($file, 'changed payload at the same name')
    Assert-Policy (-not (Test-ArtifactReceipt $build $inputs $tools @(Get-ArtifactContentRecords $temporary))) 'Same file name with changed bytes must rebuild.'
    Assert-Policy (-not (Test-ArtifactReceipt $build $inputs $tools @())) 'An absent artifact cannot reuse a successful build.'
    $path = Join-Path $temporary 'receipt.json'
    Write-LocalValidationReceipt $path $receipt
    Assert-Policy (Test-ValidationReceipt (Read-LocalValidationReceipt $path) $inputs $tools @('b')) 'Receipts must preserve coverage through durable save/load.'
} finally {
    $approved = [IO.Path]::GetFullPath((Join-Path $repo 'tool/qa-validation-pipeline')).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $resolved = [IO.Path]::GetFullPath($temporary)
    if (-not $resolved.StartsWith($approved, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

$signature = [pscustomobject]@{Schema=1; Verified=$true; Sha256='signed-bytes'; Thumbprint='expected'; TimestampServer='https://timestamp.example'; TimestampThumbprint='tsa'}
$integrity = [pscustomobject]@{Accepted=$true; TimestampThumbprint='tsa'}
Assert-Policy (Test-SignatureReceipt $signature 'signed-bytes' 'expected' 'https://timestamp.example' $integrity) 'Only an exact verified signature policy may be reused.'
foreach ($case in @(@('tampered', 'expected', 'https://timestamp.example'), @('signed-bytes', 'other', 'https://timestamp.example'), @('signed-bytes', 'expected', ''))) {
    Assert-Policy (-not (Test-SignatureReceipt $signature $case[0] $case[1] $case[2] $integrity)) 'Content/signer/timestamp policy mismatch must prevent signature reuse.'
}
Assert-Policy (-not (Test-SignatureReceipt $signature 'signed-bytes' 'expected' 'https://timestamp.example' ([pscustomobject]@{Accepted=$false; TimestampThumbprint='tsa'}))) 'A signer certificate field cannot replace signature integrity verification.'
Assert-Policy (-not (Test-SignatureReceipt $null 'signed-bytes' 'expected' 'https://timestamp.example' $integrity)) 'A prior verified full-file digest is mandatory for reuse.'

$plan = & (Join-Path $PSScriptRoot 'render_public_ui.ps1') -Page search -VerifyOnly -PlanOnly
Assert-Policy ('--dart-define=DAN_PLAYER_PUBLIC_UI_PAGE=search' -cin $plan.Arguments) 'Page selection must reach the production fixture.'
Assert-Policy (-not ($plan.Arguments -match 'EXPORT_PUBLIC_UI=true')) 'Layout-only checks must not write screenshots.'
$plan = & (Join-Path $PSScriptRoot 'render_public_ui.ps1') -TestFile test/current_playlist_view_test.dart -TestName 'render updated queue history and stop controls' -OutputDirectory (Join-Path $repo 'tool/render-updates') -PlanOnly
Assert-Policy ('--plain-name' -cin $plan.Arguments -and ($plan.Arguments -match 'DAN_PLAYER_UPDATE_RENDER_DIR=').Count -eq 1) 'Focused render selection/output must reach the chosen production fixture.'

foreach ($path in @('support/validation_receipt.ps1','support/signature_integrity.ps1','support/ci_impact.ps1','select_windows_ci_checks.ps1','build_windows_release.ps1','sign_windows_release.ps1','verify_interaction_regressions.ps1','render_public_ui.ps1')) {
    $tokens=$null; $errors=$null
    $null = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $path), [ref]$tokens, [ref]$errors)
    Assert-Policy ($errors.Count -eq 0) "PowerShell syntax errors in $path : $errors"
}
Write-Host "Validation pipeline: $checks policy checks passed (no Flutter, UI, signing or publication)."
