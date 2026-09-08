# Content-addressed receipts are local evidence, never a replacement for a
# missing check. Unknown fields, changed inputs or absent tools are cache misses.
function Get-TextSha256([string] $Text) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $hash.Dispose() }
}

function Get-ValidationInputs([string] $RepositoryRoot, [switch] $BuildOnly) {
    $paths = @(& git -C $RepositoryRoot -c core.quotepath=false ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inventory source inputs for validation reuse.' }
    $records = @()
    foreach ($relative in ($paths | Sort-Object -Unique)) {
        if ($relative -notmatch '^(lib/|rust/|rust_builder/|windows/|assets/|third_party/|scripts/|test/|\.github/|pubspec\.|analysis_options\.)') { continue }
        if ($BuildOnly -and $relative -match '(^test/|/test/|/tests/|^\.github/)') { continue }
        if ($relative -match '(?i)\.(md|txt)$' -and $relative -notmatch 'CMakeLists\.txt$') { continue }
        $full = Join-Path $RepositoryRoot $relative
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            $records += "$relative`t$((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash)"
        } else { $records += "$relative`tDELETED" }
    }
    foreach ($relative in @('.dart_tool/package_config.json', 'third_party/desktop_lyric/.dart_tool/package_config.json')) {
        $full = Join-Path $RepositoryRoot $relative
        if (Test-Path -LiteralPath $full -PathType Leaf) { $records += "$relative`t$((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash)" }
    }
    $head = (& git -C $RepositoryRoot rev-parse HEAD | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record source revision.' }
    $status = @(& git -C $RepositoryRoot -c core.quotepath=false status --porcelain --untracked-files=all)
    return [pscustomobject]@{ Hash = Get-TextSha256 ($records -join "`n"); Revision = $head; Worktree = $status; FileCount = $records.Count }
}

function Get-ValidationToolchain([string] $Flutter, [switch] $Native) {
    $flutterVersion = @(& $Flutter --version --machine 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot fingerprint Flutter/Dart.' }
    $tools = [ordered]@{ Flutter = $flutterVersion }
    if ($Native) {
        foreach ($command in @(@('rustup', 'run', 'stable', 'rustc', '-vV'), @('cmake', '--version'))) {
            $executable = $command[0]
            $arguments = $command[1..($command.Length - 1)]
            $text = @(& $executable @arguments 2>&1) -join "`n"
            if ($LASTEXITCODE -ne 0) { throw "Cannot fingerprint $executable" }
            $tools[$executable] = $text
        }
        # CMake's selected compiler and SDK are also content inputs after the
        # first configure. The actual build tree is checked separately below.
        $tools['VisualStudio'] = $env:VCToolsVersion
        $tools['WindowsSdk'] = $env:WindowsSDKVersion
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
        if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) { throw 'Cannot fingerprint the installed MSVC toolchain.' }
        $installation = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $installation) { throw 'No MSVC installation was found.' }
        $compilerVersion = [IO.File]::ReadAllText((Join-Path $installation 'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt')).Trim()
        $compiler = Join-Path $installation "VC/Tools/MSVC/$compilerVersion/bin/Hostx64/x64/cl.exe"
        $tools['CompilerHash'] = (Get-FileHash -LiteralPath $compiler -Algorithm SHA256).Hash
        $tools['CompilerVersion'] = $compilerVersion
        $sdkVersion = (Get-ChildItem -LiteralPath (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/Include') -Directory | Sort-Object Name -Descending | Select-Object -First 1).Name
        $tools['InstalledWindowsSdk'] = $sdkVersion
    }
    return [pscustomobject]@{ Hash = Get-TextSha256 ($tools | ConvertTo-Json -Compress); Details = $tools }
}

function Test-ValidationReceipt($Receipt, $Inputs, $Toolchain, [string[]] $RequiredTests) {
    try {
        if ($null -eq $Receipt -or $Receipt.Schema -ne 1 -or $Receipt.Passed -ne $true -or
            $Receipt.Inputs.Hash -cne $Inputs.Hash -or $Receipt.Toolchain.Hash -cne $Toolchain.Hash) { return $false }
        foreach ($test in $RequiredTests) { if ($test -cnotin $Receipt.Tests) { return $false } }
        return $true
    } catch { return $false }
}

function Read-LocalValidationReceipt([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { return $null }
}

function Write-LocalValidationReceipt([string] $Path, $Value) {
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Get-ArtifactContentRecords([string] $Directory) {
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return @() }
    $root = [IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')
    if (((Get-Item -LiteralPath $root).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Artifact root must not be a reparse point.' }
    $records = @()
    foreach ($file in (Get-ChildItem -LiteralPath $root -Recurse -Force | Sort-Object FullName)) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Artifact tree contains a reparse point.' }
        if ($file.PSIsContainer) { continue }
        $records += [pscustomobject]@{ Path = $file.FullName.Substring($root.Length + 1).Replace('\', '/'); Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
    }
    return $records
}

function Test-ArtifactReceipt($Receipt, $Inputs, $Toolchain, [object[]] $Records) {
    try {
        if (-not (Test-ValidationReceipt $Receipt $Inputs $Toolchain @()) -or $Records.Count -eq 0) { return $false }
        return (Get-TextSha256 ($Records | ConvertTo-Json -Compress)) -ceq $Receipt.ArtifactHash
    } catch { return $false }
}
