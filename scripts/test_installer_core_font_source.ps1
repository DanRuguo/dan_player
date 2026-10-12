#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string] $QaDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repository = Split-Path -Parent $PSScriptRoot
$workspace = Split-Path -Parent $repository
. (Join-Path $PSScriptRoot 'support\bundled_fonts.ps1')
. (Join-Path $PSScriptRoot 'support\slim_installer_payload.ps1')
$installerFont = Get-BundledInstallerFont -RepositoryRoot $repository
$qa = [IO.Path]::GetFullPath($QaDirectory)
$qaPrefix = (Join-Path $workspace 'tool\qa-local').TrimEnd('\', '/') + '\'
if (-not $qa.StartsWith($qaPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Font fixtures must remain inside workspace QA.'
}
$ancestor = $qa
while ($ancestor) {
    if ((Test-Path -LiteralPath $ancestor) -and
        ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Refusing a QA reparse point.'
    }
    $parent = Split-Path -Parent $ancestor
    if ($parent -eq $ancestor) { break }
    $ancestor = $parent
}

# Execute the actual core enumeration and output-entry generation without
# invoking the compiler, signing, native validation, or the packaging script.
$buildPath = Join-Path $PSScriptRoot 'build_windows_installer.ps1'
$tokens = $null; $parseErrors = $null
$buildAst = [Management.Automation.Language.Parser]::ParseFile($buildPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Installer build script did not parse.' }
$coreLoops = @($buildAst.FindAll({ param($node)
    $node -is [Management.Automation.Language.ForEachStatementAst] -and
    $node.Variable.VariablePath.UserPath -ceq 'file' -and
    $node.Condition.Extent.Text.Contains('Get-ChildItem') -and
    $node.Condition.Extent.Text.Contains('$PayloadDirectory')
}, $true))
$outputLoops = @($buildAst.FindAll({ param($node)
    $node -is [Management.Automation.Language.ForEachStatementAst] -and
    $node.Variable.VariablePath.UserPath -ceq 'entry' -and
    $node.Body.Extent.Text.Contains('PayloadInstalled(') -and
    $node.Body.Extent.Text.Contains('$fileEntries.Add(')
}, $true))
$quoteFunctions = @($buildAst.FindAll({ param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -ceq 'Quote-Inno'
}, $true))
if ($coreLoops.Count -ne 1 -or $outputLoops.Count -ne 1 -or $quoteFunctions.Count -ne 1) {
    throw 'Cannot identify the production core enumeration and output generation.'
}
$coreEnumeration = [scriptblock]::Create($coreLoops[0].Extent.Text)
$outputGeneration = [scriptblock]::Create($outputLoops[0].Extent.Text)
. ([scriptblock]::Create($quoteFunctions[0].Extent.Text))

$run = Join-Path $qa ('core-font-source-' + [Guid]::NewGuid().ToString('N'))
$portable = Join-Path $run 'portable'
$fontCopy = Join-Path $portable $installerFont.PayloadRelativePath
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $fontCopy) -Force
Copy-Item -LiteralPath $installerFont.SourcePath -Destination $fontCopy
foreach ($record in @(
    @('Dan Player.exe', 'synthetic player bytes'),
    @('tool/ffmpeg/ffmpeg.exe', 'optional component bytes')
)) {
    $file = Join-Path $portable $record[0]
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force
    [IO.File]::WriteAllText($file, $record[1], [Text.UTF8Encoding]::new($false))
}
$portablePrefix = $portable.TrimEnd('\', '/') + '\'
$auditedEntries = @(foreach ($file in Get-ChildItem -LiteralPath $portable -Recurse -File | Sort-Object FullName) {
    $relative = $file.FullName.Substring($portablePrefix.Length).Replace('\', '/')
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $source = Get-InstallerPayloadSource -RelativePath $relative -SourcePath $file.FullName -Sha256 $hash -Bytes $file.Length -InstallerFont $installerFont
    [pscustomobject]@{ Relative=$relative; Source=$source; Hash=$hash; Length=$file.Length }
})

function Read-ProductionCoreEntries([string] $Directory) {
    $PayloadDirectory = $Directory
    $payloadPrefix = $Directory.TrimEnd('\', '/') + '\'
    $entries = [Collections.Generic.List[object]]::new()
    $totalBytes = [uint64]0
    . $coreEnumeration
    $manifestText = "DANPLAYER_PAYLOAD_V1`n26.1.1`n"
    $fileEntries = [Collections.Generic.List[string]]::new()
    . $outputGeneration
    [pscustomobject]@{ Entries=$entries.ToArray(); Manifest=$manifestText; FileEntries=$fileEntries.ToArray(); Bytes=$totalBytes }
}
function Assert-FontCase([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}
$failures = [Collections.Generic.List[string]]::new()
$passed = 0
function Run-FontCase([string] $Name, [scriptblock] $Action) {
    try {
        & $Action
        $script:passed++
        Write-Output "PASS $Name"
    } catch {
        $failures.Add($Name)
        Write-Output "FAIL ${Name}: $($_.Exception.Message)"
    }
}

$core = New-SlimInstallerPayload -Entries $auditedEntries -Destination (Join-Path $run 'core')
$coreEntries = Read-ProductionCoreEntries $core
$runtimeFont = @($coreEntries.Entries | Where-Object Relative -CEQ $installerFont.PayloadRelativePath)
Run-FontCase 'slim runtime font shares the wizard canonical source' {
    Assert-FontCase ($runtimeFont.Count -eq 1) 'Expected exactly one runtime font entry.'
    Assert-FontCase ($runtimeFont[0].Source -ceq $installerFont.SourcePath) 'Slim enumeration lost the shared canonical source.'
    Assert-FontCase ($runtimeFont[0].Hash -ceq $installerFont.Sha256 -and $runtimeFont[0].Length -eq $installerFont.Bytes) 'Runtime font bytes or audit metadata changed.'
}
Run-FontCase 'runtime font keeps its manifest destination and install callback' {
    $manifestRecord = "{0}`t{1}`t{2}`n" -f $installerFont.Sha256, $installerFont.Bytes, $installerFont.PayloadRelativePath
    Assert-FontCase ($coreEntries.Manifest.Contains($manifestRecord)) 'Runtime font manifest changed.'
    $fontLine = @($coreEntries.FileEntries | Where-Object { $_.Contains('DestName: "PingFangSC-Regular.ttf"') })
    Assert-FontCase ($fontLine.Count -eq 1) 'Runtime font output entry is missing or duplicated.'
    Assert-FontCase ($fontLine[0].Contains('DestDir: "{app}\data\flutter_assets\packages\desktop_lyric\assets\fonts"')) 'Runtime destination changed.'
    Assert-FontCase ($fontLine[0].Contains("AfterInstall: PayloadInstalled(ExpandConstant('{app}\data\flutter_assets\packages\desktop_lyric\assets\fonts\PingFangSC-Regular.ttf'))")) 'Runtime installation callback changed.'
    Assert-FontCase ($fontLine[0].Contains('Flags: ignoreversion; Check: ContinueInstall;')) 'Runtime installation flags changed.'
}
Run-FontCase 'non-font payload retains its audited stage source and optional exclusion' {
    $player = @($coreEntries.Entries | Where-Object Relative -CEQ 'Dan Player.exe')
    Assert-FontCase ($player.Count -eq 1 -and $player[0].Source -ceq (Join-Path $core 'Dan Player.exe')) 'Unrelated payload source changed.'
    Assert-FontCase (@($coreEntries.Entries | Where-Object { Test-OptionalPlayerComponentPath $_.Relative }).Count -eq 0) 'Optional component entered the core.'
}
foreach ($defect in @('hash', 'length')) {
    $damaged = New-SlimInstallerPayload -Entries $auditedEntries -Destination (Join-Path $run ('core-' + $defect))
    $damagedFont = Join-Path $damaged $installerFont.PayloadRelativePath
    $stream = [IO.File]::Open($damagedFont, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite)
    try {
        if ($defect -eq 'hash') {
            $stream.Position = 17
            $original = $stream.ReadByte()
            $stream.Position = 17
            $stream.WriteByte(($original + 1) % 256)
        } else {
            $stream.Position = $stream.Length
            $stream.WriteByte(0)
        }
    } finally { $stream.Dispose() }
    Run-FontCase ("damaged stage font $defect is rejected before canonical substitution") {
        $rejected = $false
        try { $null = Read-ProductionCoreEntries $damaged } catch {
            if ($_.Exception.Message -cne 'Runtime installer font differs from its pinned original.') { throw }
            $rejected = $true
        }
        Assert-FontCase $rejected 'Canonical authority must not hide damaged stage bytes.'
    }
}
Assert-FontCase ((Get-FileHash -LiteralPath $fontCopy -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $installerFont.Sha256) 'Portable font was changed.'
Assert-FontCase ((Get-FileHash -LiteralPath $installerFont.SourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $installerFont.Sha256) 'Canonical font was changed.'
Write-Output "$passed passed, $($failures.Count) failed"
if ($failures.Count) { throw 'Installer core font source regression failed.' }
