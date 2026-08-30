# UI localization: catalog A and display-boundary QA

## Catalog

- `third_party/desktop_lyric/lib/l10n/ui_catalog_a.dart` contains exactly the
  first **250** unique `text` values in `build/ui-strings.json`, preserving
  first-appearance order, every original key, and all embedded line breaks.
- Every key has English, Japanese and Korean translations: **750** values.
  All **62** source placeholder occurrences are preserved in each language.
- `ui_catalog_a_extra.dart` adds **35** display-boundary keys (**105** translated
  values), including comment totals, enum labels, built-in provider names,
  equalizer presets and application-owned comment error messages.
- Translations were authored locally, without sending text to an external
  translation service. The source inventory contains application UI copy, not
  user music or comments.

Read-only structural verification:

```text
dart run tool/qa-ui-catalog/verify_catalog_a.dart
```

The verifier passed exact key/order checks, nonempty three-language rows,
placeholder multiset checks and original catalog line-break checks. Extra
rows also passed three-language and placeholder checks.

## Display fixes

- Search filter, comment sort and comment-association enum labels are
  translated at the display boundary, without changing enum values, query
  strings, sort behavior or persisted IDs.
- Comment totals translate both the outer message and its platform-total
  suffix. Missing composer credit is translated; actual title/artist/album
  text is never passed to the translation lookup.
- Cached lyric/comment UI errors retain a deferred message, so a language
  change updates the display without redoing the search or network request.
- Equalizer preset names are translated only for display. Internal preset
  keys remain stable. In particular, reset uses the internal flat-preset key,
  not its translated label. Only the dropdown's cached display controller is
  refreshed when language changes; equalizer state and gains are retained.
- The mini player's absent-artist fallback is translated on display. An
  actual artist string equal to that fallback is still shown verbatim.
- Playback mode and shuffle tooltip arguments now translate their UI-only
  state labels, rather than embedding Chinese labels inside a translated
  outer template.

Dynamic service diagnostics (for example an HTTP error string assembled by a
service) remain raw diagnostic arguments. This bounded pass does not regex-
translate arbitrary strings or modify service/domain IDs to infer templates.

## Tests

Six focused suites passed **92/92**:

```text
ui_display_localization_test.dart
song_comments_dialog_test.dart
song_comment_match_dialog_test.dart
lyric_source_dialog_test.dart
compact_player_test.dart
short_settings_dialog_test.dart
```

The **10 new cases** verify all three non-Chinese languages, all four languages
at 507×320 / 200% text for the equalizer, preset/reset behavior, stable search
queries, comment totals, cached errors without extra requests, unchanged media
and comment strings (including text that happens to equal a UI key), retained
widget state, and mini-player fallback handling. Existing regressions continue
to cover stale callbacks, cancellation, scroll positions, short dialogs and
large text. New catalog/test/verifier files passed scoped analysis with no
issues. No GUI or actual user media/settings/library was accessed.
