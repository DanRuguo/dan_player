[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $ProjectRoot,
    [Parameter(Mandatory = $true)] [string] $Flutter
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$resolvedProject = (Resolve-Path -LiteralPath $ProjectRoot).Path
$dependencyOutput = [System.Collections.Generic.List[string]]::new()
Push-Location $resolvedProject
try {
    & $Flutter pub get 2>&1 | ForEach-Object {
        $line = $_.ToString()
        $dependencyOutput.Add($line)
        Write-Host $line
    }
    $dependencyExitCode = $LASTEXITCODE

    # Flutter has already resolved packages and generated plugin metadata before
    # it asks Windows to create symlinks. Directory junctions work without
    # Developer Mode and do not require changing the machine's security policy.
    if ($dependencyExitCode -ne 0 -and
        ($dependencyOutput -join "`n") -notmatch 'Building with plugins requires symlink support') {
        throw "flutter pub get failed in $resolvedProject (exit $dependencyExitCode)."
    }

    $metadataPath = Join-Path $resolvedProject '.flutter-plugins-dependencies'
    $packageConfig = Join-Path $resolvedProject '.dart_tool\package_config.json'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $packageConfig -PathType Leaf)) {
        throw 'Flutter did not finish resolving dependencies before the symlink failure.'
    }
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    foreach ($platform in @('windows', 'linux')) {
        $platformRoot = Join-Path $resolvedProject $platform
        if (-not (Test-Path -LiteralPath $platformRoot -PathType Container)) { continue }
        $platformProperty = $metadata.plugins.PSObject.Properties[$platform]
        if (-not $platformProperty) { continue }
        $linkRoot = Join-Path $platformRoot 'flutter\ephemeral\.plugin_symlinks'
        $null = New-Item -ItemType Directory -Path $linkRoot -Force

        foreach ($plugin in $platformProperty.Value) {
            if ($plugin.name -notmatch '^[a-zA-Z0-9_]+$') {
                throw "Invalid plugin name in generated metadata: $($plugin.name)"
            }
            $targetPath = (Resolve-Path -LiteralPath $plugin.path).Path
            $linkPath = Join-Path $linkRoot $plugin.name
            if (Test-Path -LiteralPath $linkPath) {
                $existing = Get-Item -LiteralPath $linkPath -Force
                if (-not $existing.LinkType -or
                    -not ([string]$existing.Target).TrimEnd('\').Equals(
                        $targetPath.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Refusing to replace an unexpected plugin path: $linkPath"
                }
                continue
            }
            $null = New-Item -ItemType Junction -Path $linkPath -Target $targetPath
        }
    }
    Write-Host 'Plugin directory junctions are ready; no system settings were changed.'
} finally {
    Pop-Location
}
