[CmdletBinding()]
param(
    [string] $ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string] $Flutter = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tool\flutter\bin\flutter.bat'),
    [ValidateSet('Development', 'Integration', 'Release')] [string] $Scope = 'Release',
    [string[]] $TestFile,
    [switch] $NoReuse,
    [string] $ReceiptPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'support/validation_receipt.ps1')
if (-not $ReceiptPath) { $ReceiptPath = Join-Path (Split-Path -Parent $ProjectRoot) 'tool/validation/flutter-checks.json' }
# Small release gate, separate from CI's full Flutter suite. These tests use
# isolated fixtures and widget layouts, never the installed player or GUI input.
$regressionTests = @(
    'test/theme_mode_preference_test.dart',
    'test/title_bar_window_state_test.dart',
    'test/desktop_window_corners_test.dart',
    'test/audio_metadata_update_test.dart',
    'test/audio_metadata_dialog_save_test.dart',
    'test/audio_menu_metadata_test.dart',
    'test/audio_deletion_action_test.dart',
    'test/audio_tile_layout_test.dart',
    'test/bass_local_open_nonblocking_test.dart',
    'test/wasapi_persistent_output_test.dart',
    'test/playback_exclusive_startup_test.dart',
    'test/play_service_shutdown_test.dart',
    'test/now_playing_bar_controls_test.dart',
    'test/now_playing_bar_layout_test.dart',
    'test/now_playing_seek_test.dart',
    'test/next_play_animation_test.dart',
    'test/now_playing_bar_transition_test.dart',
    'test/rectangle_progress_indicator_test.dart',
    'test/update_service_test.dart',
    'test/update_channel_test.dart',
    'test/update_preferences_persistence_test.dart',
    'test/installer_launcher_test.dart',
    'test/playlist_detail_controls_test.dart',
    'test/taskbar_peek_quality_test.dart',
    'test/app_dialog_title_test.dart',
    'test/app_presentation_test.dart',
    'test/dialog_navigator_lifecycle_test.dart',
    'test/help_navigator_scope_test.dart',
    'test/app_shutdown_presentation_test.dart',
    'test/app_shutdown_retry_test.dart',
    'test/app_shutdown_visibility_retry_test.dart',
    'test/update_flow_test.dart',
    'test/window_corners_paused_settings_test.dart',
    'test/incremental_library_refresh_test.dart',
    'test/incremental_refresh_controls_test.dart',
    'test/app_content_scrollbar_test.dart',
    'test/online_metadata_dialog_layout_test.dart',
    'test/short_search_dialog_test.dart',
    'test/short_settings_dialog_test.dart',
    'test/title_bar_lyric_alignment_test.dart',
    'test/desktop_lyric_palette_lifecycle_test.dart',
    'test/desktop_lyric_palette_bridge_test.dart',
    'test/desktop_lyric_palette_theme_test.dart',
    'test/desktop_lyric_palette_reuse_test.dart',
    'test/desktop_lyric_theme_startup_test.dart',
    'test/desktop_lyric_appearance_options_test.dart',
    'test/desktop_lyric_appearance_persistence_test.dart',
    'test/desktop_lyric_settings_test.dart',
    'test/taskbar_lyric_mode_test.dart',
    'test/ui_language_test.dart',
    'test/ui_display_localization_test.dart',
    'test/desktop_lyric_locale_layout_test.dart',
    'test/ui_language_library_layout_test.dart',
    'test/ui_layout_views_test.dart',
    'test/hidden_rendering_lifecycle_test.dart',
    'test/rendering_preferences_test.dart',
    'test/rendering_preferences_persistence_test.dart',
    'test/rendering_visibility_lifecycle_test.dart',
    'test/rendering_visibility_hosts_test.dart',
    'test/app_segmented_control_test.dart',
    'test/app_segmented_control_paint_test.dart',
    'test/music_toolbar_alignment_test.dart',
    'test/music_grid_test.dart',
    'test/settings_presentation_test.dart',
    'test/taskbar_preview_color_test.dart',
    'test/taskbar_song_preview_test.dart',
    'test/app_control_theme_test.dart',
    'test/playlist_circle_view_test.dart',
    'test/playlist_browser_test.dart',
    'test/desktop_integration_settings_test.dart',
    'test/tray_menu_blur_test.dart',
    'test/tray_menu_blur_persistence_test.dart',
    'test/uni_detail_responsive_language_test.dart',
    'test/uni_page_locate_responsive_test.dart',
    'test/playlist_circle_readonly_test.dart',
    'test/unified_playlists_ui_test.dart',
    'test/current_playlist_view_test.dart',
    'test/queue_undo_test.dart',
    'test/queue_stop_boundary_test.dart',
    'test/guarded_playback_seek_test.dart'
)
if ($Scope -eq 'Development') {
    if (-not $TestFile -or $TestFile.Count -eq 0) { throw 'Development validation requires explicit -TestFile coverage.' }
    $regressionTests = $TestFile
} elseif ($Scope -eq 'Integration') {
    $regressionTests = @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'test') -Recurse -File -Filter '*_test.dart' | ForEach-Object {
        $_.FullName.Substring(([IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')).Length + 1).Replace('\', '/')
    })
} elseif ($TestFile) { throw '-TestFile is only allowed with Development; a release gate cannot silently narrow its required checks.' }
$regressionTests = @($regressionTests | Sort-Object -Unique)
Push-Location $ProjectRoot
try {
    foreach ($regressionTest in $regressionTests) {
        if (-not (Test-Path -LiteralPath $regressionTest -PathType Leaf)) {
            throw "Required interaction regression is missing: $regressionTest"
        }
    }
    $inputs = Get-ValidationInputs $ProjectRoot
    $toolchain = Get-ValidationToolchain $Flutter
    $receipt = Read-LocalValidationReceipt $ReceiptPath
    if (-not $NoReuse -and (Test-ValidationReceipt $receipt $inputs $toolchain $regressionTests)) {
        Write-Host "Reusing verified $($regressionTests.Count)-test coverage from $($receipt.CompletedAt); source content $($inputs.Hash), revision $($inputs.Revision)."
        return
    }
    if ($Scope -eq 'Integration') { & $Flutter test --no-pub --reporter expanded }
    else {
        if (($regressionTests -join ' ').Length -gt 6000) { throw 'Selected test arguments exceed the Windows batch limit; use Integration scope or a smaller explicit batch.' }
        & $Flutter test --no-pub --reporter expanded @regressionTests
    }
    if ($LASTEXITCODE -ne 0) {
        throw 'Interaction regression gate failed. Release compilation is blocked.'
    }
    $after = Get-ValidationInputs $ProjectRoot
    if ($after.Hash -cne $inputs.Hash) { throw 'Source changed during validation; result cannot be reused or released.' }
    Write-LocalValidationReceipt $ReceiptPath ([ordered]@{
        Schema=1; Passed=$true; Scope=$Scope; Inputs=$inputs; Toolchain=$toolchain;
        Tests=$regressionTests; CompletedAt=[DateTime]::UtcNow.ToString('o')
    })
} finally {
    Pop-Location
}
