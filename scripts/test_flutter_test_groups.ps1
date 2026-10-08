[CmdletBinding()]
param([string] $OutputDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'support/flutter_test_groups.ps1')
$policyRepo = Split-Path -Parent $PSScriptRoot
$policyQa = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $policyRepo) 'tool/qa-local'))
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $policyQa 'flutter-test-groups-policy' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (-not $OutputDirectory.StartsWith($policyQa.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Policy fixtures must remain inside workspace tool/qa-local.'
}
$policyFixture = Join-Path $OutputDirectory ([Guid]::NewGuid().ToString('N'))
$policyChecks = 0
function Assert-Grouping([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
    $script:policyChecks++
}
function Assert-GroupingRejects([scriptblock] $Action, [string] $Reason) {
    $rejected = $false
    try { $null = & $Action } catch { $rejected = $_.Exception.Message -like "*$Reason*" }
    Assert-Grouping $rejected "Expected fail-closed grouping: $Reason"
}
function Write-GroupingFixture([string] $Relative, [string] $Content = 'void main() {}') {
    $file = Join-Path $policyFixture $Relative
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force
    [IO.File]::WriteAllText($file, $Content)
}
$policyBefore = @($env:DAN_PLAYER_DATA_DIR, $env:TEMP, $env:TMP)
try {
    Write-GroupingFixture 'test/explicit_test.dart'
    Write-GroupingFixture 'test/nested/mock_test.dart' "const channel = 'plugins.flutter.io/path_provider';"
    Write-GroupingFixture 'test/nested/workspace_test.dart' "const variable = 'DAN_PLAYER_DATA_DIR';"
    Write-GroupingFixture 'test/ordinary_test.dart'
    Write-GroupingFixture 'test/support/helper.dart'
    Write-GroupingFixture 'integration_test/window_test.dart'
    Write-GroupingFixture 'scripts/native_tests/hardware_test.dart'
    $groups = Get-FlutterTestGroups $policyFixture -MockedDataRootTest @('explicit_test.dart')
    Assert-Grouping ($groups.Files.Count -eq 4) 'Only recursive formal unit files belong to the default suite.'
    Assert-Grouping ($groups.MockedDataRoot.Count -eq 2 -and $groups.WorkspaceDataRoot.Count -eq 2) 'Explicit and automatic mock fixtures must avoid the workspace override.'
    Assert-Grouping ('workspace_test.dart' -cin $groups.WorkspaceDataRoot.Name) 'New storage files must be covered without a fixed storage allowlist.'
    Assert-Grouping ((@($groups.Files.FullName | Sort-Object) -join "`n") -ceq ($groups.Files.FullName -join "`n")) 'Discovery ordering must remain stable for chunk continuation.'
    $selected = Get-FlutterTestGroups $policyFixture -MockedDataRootTest @('explicit_test.dart') -TestFile @('test/nested/mock_test.dart', 'test/nested/workspace_test.dart')
    Assert-Grouping ($selected.Files.Count -eq 2 -and $selected.MockedDataRoot.Count -eq 1 -and $selected.WorkspaceDataRoot.Count -eq 1) 'Selective CI coverage must retain the same isolation rules.'
    $absolute = Get-FlutterTestGroups $policyFixture -MockedDataRootTest @('explicit_test.dart') -TestFile $selected.Files.FullName
    Assert-Grouping (($absolute.Files.FullName -join "`n") -ceq ($selected.Files.FullName -join "`n")) 'Absolute discovered paths must preserve selective coverage.'
    Assert-GroupingRejects { Get-FlutterTestGroups $policyFixture -MockedDataRootTest @('removed_test.dart') } 'stale or ambiguous'
    Assert-GroupingRejects { Get-FlutterTestGroups $policyFixture -MockedDataRootTest @() -TestFile @() } 'cannot be empty'
    Assert-GroupingRejects { Get-FlutterTestGroups $policyFixture -MockedDataRootTest @() -TestFile @('test/ordinary_test.dart', 'test/nested/../ordinary_test.dart') } 'duplicated'
    Assert-GroupingRejects { Get-FlutterTestGroups $policyFixture -MockedDataRootTest @() -TestFile @('integration_test/window_test.dart') } 'outside the discovered'
    Assert-GroupingRejects { Get-FlutterTestGroups $policyFixture -MockedDataRootTest @() -TestFile @('test/support/helper.dart') } 'outside the discovered'
    Write-GroupingFixture 'test/mirror/explicit_test.dart'
    Assert-GroupingRejects { Get-FlutterTestGroups $policyFixture -MockedDataRootTest @('explicit_test.dart') } 'stale or ambiguous'

    $actual = Get-FlutterTestGroups $policyRepo
    $discovered = @(Get-ChildItem -LiteralPath (Join-Path $policyRepo 'test') -Recurse -File -Filter '*_test.dart')
    $union = @($actual.MockedDataRoot + $actual.WorkspaceDataRoot | ForEach-Object FullName)
    Assert-Grouping ($union.Count -eq $discovered.Count -and @($union | Sort-Object -Unique).Count -eq $discovered.Count) 'Every real formal test must belong to exactly one group.'
    foreach ($file in @('local_lyric_variants_test.dart', 'local_lyric_variant_source_test.dart', 'ttml_local_integration_test.dart')) {
        Assert-Grouping ($file -cin $actual.WorkspaceDataRoot.Name -and $file -cnotin $actual.MockedDataRoot.Name) "Storage isolation was omitted: $file"
    }
    Assert-Grouping (($policyBefore -join "`n") -ceq (@($env:DAN_PLAYER_DATA_DIR, $env:TEMP, $env:TMP) -join "`n")) 'Discovery must not mutate process fixture settings.'
    $workflow = [IO.File]::ReadAllText((Join-Path $policyRepo '.github/workflows/windows_ci.yml'))
    Assert-Grouping (-not $workflow.Contains('$storageTests') -and $workflow.Contains('Get-FlutterTestGroups -ProjectRoot $env:GITHUB_WORKSPACE -TestFile $tests')) 'CI full and selected checks must consume shared grouping.'
    Write-Host "Flutter grouping: $policyChecks offline policy checks passed; $($actual.Files.Count) real files ($($actual.MockedDataRoot.Count) mocked, $($actual.WorkspaceDataRoot.Count) workspace). No Flutter tests were executed."
} finally {
    $policyApproved = $OutputDirectory.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $policyResolved = [IO.Path]::GetFullPath($policyFixture)
    if (-not $policyResolved.StartsWith($policyApproved, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe policy fixture cleanup path.' }
    if (Test-Path -LiteralPath $policyResolved) { Remove-Item -LiteralPath $policyResolved -Recurse -Force }
}
