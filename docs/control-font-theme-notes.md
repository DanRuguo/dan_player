# Control typography and explicit alternatives

## Cause and fix

The application's tooltip theme supplied a standalone `TextStyle` containing
only color, size and weight. Flutter's tooltip chooses that style in preference
to its complete default style; the selected application font and fallback list
were therefore absent from the overlay. Ordinary page text still inherited the
correct font, producing a visible mismatch.

`applyAppControlTheme` now derives tooltip text from the generated theme's
complete `bodySmall` style, retaining font family/fallbacks while binding color
to `onSurface`. Global segmented controls similarly use `labelLarge`, with
selected text/background on `onPrimaryContainer` / `primaryContainer` and
unselected text on `primary`. Existing shape, tooltip spacing, timing and
palette-derived decoration are retained. The existing Entry theme factory
applies this helper to both light and dark themes. No font or media loader was
added to ThemeProvider.

## Bounded control integration

These mutually exclusive short lists use the shared `AppSegmentedControl`:

- Theme mode: explicit Light / Dark labels replace the prior icon-only pair.
- Preferred lyric source: Local / Online.
- Library row style: Classic list / Explorer columns.

They show alternatives directly when measured text fits and retain the same
choices in a menu when narrow or enlarged. Domain values, persistence handlers
and unrelated preferences remain unchanged. `catalog_controls.dart` contributes
only the two new theme labels, each in English/Japanese/Korean.

Search already shows five scrollable tabs, playback speed has more than three
options, and the lyric-source menu mixes a dialog action with state choices.
Those were deliberately not collapsed into a two/three-option selector.
Already-expanded language/background selectors and desktop/native settings
were outside this change.

## Read-only performance review

- Existing ThemeProvider tests demonstrate that 40 unchanged-track notifications
  share one artwork load and publish one atomic pair of palettes. Both palette
  extractions use the same bounded 320px image sample. These paths were not
  changed by the typography fix.
- Short-label measurement in the shared selector is bounded to its small
  option set and is not driven by an animation ticker. Its initial sum-of-label
  fit estimate was identified as incorrect: Flutter lays segmented controls
  out in equal-width segments using the largest intrinsic width. The component
  owner corrected the estimate to maximum segment width × count before QA.
- Font changes currently notify listeners even when the same family is passed
  again. This is a settings action, not a playback-frame path; no speculative
  cache or unrelated optimization was introduced. This review does not claim
  a measured CPU or memory percentage improvement.

## Verification

Four focused suites passed **72/72**, including **20 new cases**:

```text
app_control_theme_test.dart
theme_provider_test.dart
app_shape_test.dart
ui_layout_views_test.dart
```

The new suite loads the real bundled PingFang font (including a second family
alias to exercise custom-family selection), verifies non-Ahem text metrics,
and checks a 16-case light/dark × high-contrast × four-language matrix at 200%
text. Rendered tooltip and segmented text retain the complete font family and
fallbacks; foreground/background contrast is at least 4.5:1 for the tested
palettes. An already-open tooltip follows a live font/palette change without
replacing its State. The settings controls expose the correct labels and stable
values, while 320px/200% row-style menus remain usable in all four languages.

The UI-layout regression changed only the narrow settings-choice test to open
the fallback menu before choosing columns. No GUI, full build, user settings,
user library, user media or installed-font files were accessed or modified.
