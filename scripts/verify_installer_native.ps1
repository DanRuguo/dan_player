#requires -Version 5.1
<# Strict native-only installer gate. Never installs/runs the player or Inno. #>
[CmdletBinding()]
param([string] $CMake, [string] $BuildDirectory, [string] $Generator = 'Visual Studio 17 2022')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$gateRepository = Split-Path -Parent $PSScriptRoot
$gateWorkspace = Split-Path -Parent $gateRepository
if (-not $CMake) {
    $command = Get-Command cmake -ErrorAction SilentlyContinue
    if ($command) { $CMake = $command.Source }
    else { $CMake = Join-Path $gateWorkspace 'tool\vs-buildtools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' }
}
if (-not (Test-Path -LiteralPath $CMake -PathType Leaf)) { throw 'Existing CMake and MSVC are required; this gate never installs them.' }
if (-not $BuildDirectory) { $BuildDirectory = Join-Path $gateWorkspace 'tool\qa-installer\build' }
$BuildDirectory = [IO.Path]::GetFullPath($BuildDirectory)
if (-not (($BuildDirectory -split '[\\/]') -contains 'qa-installer')) { throw 'BuildDirectory must be inside an explicit qa-installer sandbox.' }
$ctest = Join-Path (Split-Path -Parent $CMake) 'ctest.exe'
$null = New-Item -ItemType Directory -Path $BuildDirectory -Force
$log = Join-Path $BuildDirectory ('native-gate-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
& $CMake -S (Join-Path $gateRepository 'installer') -B $BuildDirectory -G $Generator -A x64 2>&1 | Tee-Object -FilePath $log
if ($LASTEXITCODE -ne 0) { throw "Native configure failed: $log" }
& $CMake --build $BuildDirectory --config Release --parallel 2 2>&1 | Tee-Object -FilePath $log -Append
if ($LASTEXITCODE -ne 0) { throw "Native build failed: $log" }
& $ctest --test-dir $BuildDirectory -C Release --output-on-failure --verbose 2>&1 | Tee-Object -FilePath $log -Append
if ($LASTEXITCODE -ne 0) { throw "Native installer tests failed: $log" }
Write-Output "Native installer gate passed. Log: $log"
