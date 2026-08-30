[CmdletBinding()]
param(
    [string] $ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string] $Flutter = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tool\flutter\bin\flutter.bat')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# Small release gate, separate from CI's full Flutter suite. These tests use
# isolated fixtures and widget layouts, never the installed player or GUI input.
$regressionTests = @(
    'test/app_dialog_title_test.dart',
    'test/app_presentation_test.dart',
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
    'test/settings_presentation_test.dart',
    'test/taskbar_preview_color_test.dart',
    'test/taskbar_song_preview_test.dart',
    'test/app_control_theme_test.dart',
    'test/playlist_circle_view_test.dart',
    'test/desktop_integration_settings_test.dart',
    'test/tray_menu_blur_test.dart',
    'test/tray_menu_blur_persistence_test.dart',
    'test/uni_detail_responsive_language_test.dart',
    'test/uni_page_locate_responsive_test.dart',
    'test/playlist_circle_readonly_test.dart'
)
Push-Location $ProjectRoot
try {
    foreach ($regressionTest in $regressionTests) {
        if (-not (Test-Path -LiteralPath $regressionTest -PathType Leaf)) {
            throw "Required interaction regression is missing: $regressionTest"
        }
    }
    & $Flutter test --no-pub --reporter expanded @regressionTests
    if ($LASTEXITCODE -ne 0) {
        throw 'Interaction regression gate failed. Release compilation is blocked.'
    }
} finally {
    Pop-Location
}
