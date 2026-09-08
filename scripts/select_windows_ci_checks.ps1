[CmdletBinding()]
param([string] $BaseRevision, [string] $HeadRevision='HEAD', [switch] $Integration, [string] $OutputPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'support/ci_impact.ps1')
$changed = @()
if ($BaseRevision -and $BaseRevision -notmatch '^0+$') {
    $changed = @(& git -C $repo -c core.quotepath=false diff --name-only --no-renames $BaseRevision $HeadRevision --)
    if ($LASTEXITCODE -ne 0) { $Integration = $true }
} else { $Integration = $true }
$result = Get-WindowsCiImpact $repo $changed -ForceIntegration:$Integration
$json = $result | ConvertTo-Json -Depth 4
if ($OutputPath) {
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force
    [IO.File]::WriteAllText($OutputPath, $json)
}
if ($env:GITHUB_OUTPUT) {
    "profile=$($result.Profile)" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
}
Write-Host "CI scope: $($result.Profile) — $($result.Reason)"
return $result
