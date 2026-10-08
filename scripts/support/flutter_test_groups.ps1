# Read-only discovery shared by local and CI runners. This module never changes
# environment variables, creates fixtures, or starts a test process.
function Get-FlutterTestGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ProjectRoot,
        [string[]] $TestFile,
        [string[]] $MockedDataRootTest = @(
            'audio_duration_refresh_instance_test.dart',
            'audio_metadata_refresh_instance_test.dart',
            'audio_trim_library_test.dart',
            'audio_trim_native_integration_test.dart',
            'automatic_online_lyrics_test.dart',
            'background_image_store_test.dart',
            'background_preferences_test.dart',
            'custom_music_source_profile_test.dart',
            'desktop_lyric_appearance_persistence_test.dart',
            'first_run_preferences_test.dart',
            'lyric_manual_network_test.dart',
            'lyric_performance_integration_test.dart',
            'mini_settings_test.dart',
            'online_source_preferences_test.dart',
            'playback_state_recovery_io_test.dart',
            'playlist_circle_readonly_test.dart',
            'playlist_warning_layout_test.dart',
            'rendering_preferences_persistence_test.dart',
            'settings_persistence_failure_test.dart',
            'smart_playlist_boundary_test.dart',
            'tray_menu_blur_persistence_test.dart',
            'unified_playlist_preferences_test.dart',
            'unified_playlist_read_protection_test.dart',
            'update_preferences_persistence_test.dart'
        )
    )
    $groupRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
    $groupFiles = @(Get-ChildItem -LiteralPath (Join-Path $groupRoot 'test') -Recurse -File -Filter '*_test.dart' | Sort-Object FullName)
    $groupMockedNames = @($MockedDataRootTest + @(
        $groupFiles | Where-Object {
            ([IO.File]::ReadAllText($_.FullName)).Contains('plugins.flutter.io/path_provider')
        } | ForEach-Object Name
    ) | Sort-Object -Unique)
    foreach ($groupName in $groupMockedNames) {
        if (@($groupFiles | Where-Object Name -eq $groupName).Count -ne 1) {
            throw "Test classification is stale or ambiguous: $groupName"
        }
    }
    $groupSelected = $groupFiles
    if ($PSBoundParameters.ContainsKey('TestFile')) {
        if (-not $TestFile -or $TestFile.Count -eq 0) { throw 'Selected test coverage cannot be empty.' }
        $groupKnown = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($groupFile in $groupFiles) { $null = $groupKnown.Add($groupFile.FullName) }
        $groupSelection = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($groupPath in $TestFile) {
            $groupAbsolute = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($groupPath)) {
                $groupPath
            } else { Join-Path $groupRoot $groupPath }))
            if (-not $groupKnown.Contains($groupAbsolute)) { throw "Selected test is outside the discovered suite: $groupPath" }
            if (-not $groupSelection.Add($groupAbsolute)) { throw "Selected test is duplicated: $groupPath" }
        }
        $groupSelected = @($groupFiles | Where-Object { $groupSelection.Contains($_.FullName) })
    }
    $groupMocked = @($groupSelected | Where-Object { $groupMockedNames -contains $_.Name })
    $groupWorkspace = @($groupSelected | Where-Object { $groupMockedNames -notcontains $_.Name })
    if ($groupMocked.Count + $groupWorkspace.Count -ne $groupSelected.Count) { throw 'Test groups do not cover the selected suite exactly once.' }
    return [pscustomobject]@{
        Files = @($groupSelected)
        MockedDataRoot = $groupMocked
        WorkspaceDataRoot = $groupWorkspace
    }
}
