# Unknown changes deliberately select integration. Only documentation and
# understood Dart-only dependency closures may take a lighter path.
function Get-WindowsCiImpact([string] $RepositoryRoot, [string[]] $ChangedPath, [switch] $ForceIntegration) {
    $changed = @($ChangedPath | ForEach-Object { $_.Replace('\', '/') } | Sort-Object -Unique)
    $integration = [pscustomobject]@{ Profile='integration'; Reason='Shared, native, unknown or explicit integration input'; Tests=@(); Changed=$changed }
    if ($ForceIntegration -or $changed.Count -eq 0) { return $integration }
    $documents = @($changed | Where-Object { $_ -match '^(README[^/]*\.md|LICENSE(?:\.(txt|md))?|docs/.*\.(md|txt))$' })
    if ($documents.Count -eq $changed.Count) {
        return [pscustomobject]@{ Profile='documents'; Reason='Explanatory documentation only'; Tests=@(); Changed=$changed }
    }
    $code = @($changed | Where-Object { $_ -cnotin $documents })
    # These inputs cross the shared engine/native/visual/build boundary. All
    # third_party changes include desktop-lyric checks and its native harness.
    $shared = '^(third_party/|windows/|rust/|rust_builder/|assets/|scripts/|\.github/|installer/|pubspec\.|analysis_options\.|lib/(main|entry|app_|theme_|utils|hotkeys|window_|rendering_|background_|desktop_integration)|lib/(src|update)/|lib/page/(updating_page|settings_page/check_update)|lib/component/(app_|title_bar|full_width_spectrum|horizontal_lyric)|lib/play_service/(playback_service|play_service|desktop_lyric_service))'
    foreach ($path in $code) {
        if ($path -match $shared -or $path -notmatch '^(lib/|test/).+\.dart$' -or
            -not (Test-Path -LiteralPath (Join-Path $RepositoryRoot $path) -PathType Leaf)) { return $integration }
    }
    # Follow real import/export/part edges, not filenames alone. Every changed
    # production file must lead to at least one test; otherwise expand scope.
    $files = @(& git -C $RepositoryRoot -c core.quotepath=false ls-files --cached --others --exclude-standard -- lib test)
    if ($LASTEXITCODE -ne 0) { return $integration }
    $reverse = @{}
    foreach ($file in ($files | Sort-Object -Unique)) {
        if ($file -notmatch '\.dart$' -or -not (Test-Path -LiteralPath (Join-Path $RepositoryRoot $file) -PathType Leaf)) { continue }
        $text = [IO.File]::ReadAllText((Join-Path $RepositoryRoot $file))
        foreach ($directive in [regex]::Matches($text, '(?:import|export|part)\s+(?!of\b)([^;]+);')) {
          foreach ($match in [regex]::Matches($directive.Groups[1].Value, '[''"]([^''"]+)[''"]')) {
            $uri = $match.Groups[1].Value
            if ($uri.StartsWith('package:dan_player/')) { $dependency = 'lib/' + $uri.Substring(19) }
            elseif ($uri -notmatch '^\w+:') {
                $absolute = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent (Join-Path $RepositoryRoot $file)) $uri))
                $prefix = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
                if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $integration }
                $dependency = $absolute.Substring($prefix.Length).Replace('\', '/')
            } else { continue }
            if (-not $reverse.ContainsKey($dependency)) { $reverse[$dependency] = [Collections.Generic.List[string]]::new() }
            $reverse[$dependency].Add($file)
          }
        }
    }
    $tests = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in $code) {
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $pending = [Collections.Generic.Queue[string]]::new()
        $pending.Enqueue($path)
        $covered = $false
        while ($pending.Count -gt 0) {
            $current = $pending.Dequeue()
            if (-not $seen.Add($current)) { continue }
            if ($current -match '^test/.+_test\.dart$') { $null = $tests.Add($current); $covered = $true }
            if ($reverse.ContainsKey($current)) { foreach ($parent in $reverse[$current]) { $pending.Enqueue($parent) } }
        }
        if (-not $covered) { return $integration }
    }
    return [pscustomobject]@{ Profile='business'; Reason='Dart-only reverse dependency closure'; Tests=@($tests | Sort-Object);
        AllDartTests=((($tests | Sort-Object) -join ' ').Length -gt 6000); Changed=$changed }
}
