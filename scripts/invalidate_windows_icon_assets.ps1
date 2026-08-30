#requires -Version 5.1
<#
Invalidate only Flutter's release asset and AOT target stamps. Flutter 3.47.1's Windows
release asset inputs omit app.dill, so a Dart-only rebuild can retain an older
tree-shaken icon subset. Also regenerate AOT: a native-only incremental build
can rewrite an identical kernel while retaining older AOT, which breaks the
font gate's strict same-build provenance check. Keep that gate fail-closed.
No font, application source, kernel, user data or previous release is removed.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string] $ProjectRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$iconProject = (Resolve-Path -LiteralPath $ProjectRoot).Path
$iconProjectItem = Get-Item -LiteralPath $iconProject -Force
if (($iconProjectItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing a redirected project root.' }
$iconToolDirectory = Join-Path $iconProject '.dart_tool'
if (Test-Path -LiteralPath $iconToolDirectory -PathType Container) {
    $iconToolItem = Get-Item -LiteralPath $iconToolDirectory -Force
    if (($iconToolItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing a redirected .dart_tool directory.' }
}
$iconCache = Join-Path $iconProject '.dart_tool\flutter_build'
if (-not (Test-Path -LiteralPath $iconCache -PathType Container)) { return }
$iconCache = (Resolve-Path -LiteralPath $iconCache).Path
$iconCacheItem = Get-Item -LiteralPath $iconCache -Force
if (($iconCacheItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing a redirected Flutter build cache.' }
$iconCachePrefix = $iconCache.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
foreach ($buildDirectory in Get-ChildItem -LiteralPath $iconCache -Directory -Force) {
    if ($buildDirectory.Name -notmatch '^[0-9a-fA-F]{32}$') { continue }
    if (($buildDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing a redirected Flutter build directory.' }
    foreach ($stampName in @('release_bundle_windows-x64_assets.stamp', 'aot_elf_release.stamp', 'windows_aot_bundle.stamp')) {
        $iconStamp = Join-Path $buildDirectory.FullName $stampName
        if (-not (Test-Path -LiteralPath $iconStamp -PathType Leaf)) { continue }
        $iconStampItem = Get-Item -LiteralPath $iconStamp -Force
        $resolvedIconStamp = [IO.Path]::GetFullPath($iconStampItem.FullName)
        if (-not $resolvedIconStamp.StartsWith($iconCachePrefix, [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($resolvedIconStamp) -ne $stampName -or
            ($iconStampItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing unexpected release cache target: $resolvedIconStamp"
        }
        if ($PSCmdlet.ShouldProcess($resolvedIconStamp, 'Invalidate generated Flutter release stamp')) {
            Remove-Item -LiteralPath $resolvedIconStamp -Force
            Write-Host "Invalidated generated release stamp: $resolvedIconStamp"
        }
    }
}
