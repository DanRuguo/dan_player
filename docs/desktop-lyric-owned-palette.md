# Desktop lyric appearance: independent owned window

## Diagnosis and scope

The old appearance route expanded the transparent lyric HWND to hold a Flutter
dialog, then restored it. `window_manager` 0.5.2 performs one `SetWindowPos` with
flags `0`; the runner handles `WM_SIZE` with `MoveWindow` on its Flutter child.
The platform-method Future completing, or Flutter `endOfFrame`, does not prove
the resized native surface and raster frame have caught up. Releasing the old
presentation latch could therefore treat expanded constraints as the normal
lyric surface for a frame. The old fake synchronized resize and test metrics,
so its passing results did not exclude this real ordering race.

The runner also restored its child focus on **every** `WM_ACTIVATE`, including
`WA_INACTIVE`. An owned appearance window would make the lyric owner lose
activation, so that code could steal focus back. It now restores child focus
only on activation.

## Implementation

- Appearance uses one on-demand `AppearancePaletteWindow`, an opaque owned
  tool HWND with a separate `FlutterViewController` and the same bundled Dart
  app's `desktopLyricAppearanceMain` entrypoint. The child is shown only after
  its first Flutter frame. After an acknowledged normal close, at most one
  hidden panel is retained for 120 seconds for fast reopening; timeout, failure
  or owner shutdown destroys it. No startup prewarming or extra package.
- Opening/closing this panel never changes the lyric HWND's size, minimum,
  position, opacity or visibility. Normal user-requested font/mode/dock-size
  changes and monitor changes still use the normal lyric layout controller.
  There is no production same-HWND fallback when creation fails.
- The child does not register window/audio/file plugins, initialize
  `window_manager`, read stdin, run the lyric playback clock or access settings.
  It reuses the existing appearance/taskbar options and immutable model.
- The lyric engine remains the sole persistence/pipe owner. Snapshots include
  theme, font, language, appearance and save/layout error state. Slider edits
  are coalesced (33 ms) field patches, with one in-flight edit and bounded field
  maps. An edit to opacity cannot overwrite a newer unrelated owner color.
  The final patch is acknowledged before a requested close; failed sends remain
  visible and retryable. Changing a color no longer closes the panel.
- Session IDs, revisions, acknowledgements, complete snapshot validation and
  disposal guards reject old replies/closed callbacks. A failed update from an
  old session cannot close a newly reopened panel. Native close marks the
  session terminal before queued destruction, so a late first frame cannot
  show it again.
- The cold entry receives a bounded StandardMessageCodec snapshot in its Dart
  entry arguments, eliminating the pre-runApp ready round trip. Changes during
  startup are revision-checked and refreshed before display. An immediate,
  theme-colored button progress indicator distinguishes loading from no action.
- A warm reopen atomically resets session/edit/closing state. Old replies cannot
  change a new session. While hidden, there are no owner snapshot messages,
  enabled tickers, focused inputs or edit timers. Reopening requests one forced
  layout frame (the HWND is still hidden), then a native fresh raster before
  showing it; this is not a recurring background rendering loop. Theme and
  language are current and fully opaque on the first displayed frame.
- A native 16-logical-pixel rounded window region, updated for DPI/size, clips
  the opaque panel on Windows 10 and 11; Flutter uses the matching ClipRRect.
  No layered transparency or undocumented DWM/taskbar APIs are introduced.
- Native teardown detaches handlers and invalidates callbacks before destroying
  the child engine. Reentrant native operations retain local shared ownership;
  HWND/lifetime checks follow focus/child-layout steps. Owner shutdown destroys
  the owned child, which never posts `WM_QUIT` for the helper.
- The lyric body no longer infers a content rectangle from asynchronous native
  metrics. It only latches hover while the panel is open. Native close supplies
  the actual cursor-within-owner state; border, shadow and background use one
  animation value instead of abrupt border/shadow toggles. Reduced motion still
  applies immediately.

The older `setPaletteOpen` geometry API remains covered by legacy layout unit
tests, but the appearance button/host no longer calls it. Those legacy tests
are not evidence for this window architecture.

## Warm reuse verification (2026-08-30 evening)

- Full Flutter suite: 2114/2114. Palette-specific protocol/lifecycle/theme/reuse:
  40/40, including 20 sequential client sessions, stale success/failure replies,
  seeded startup, a forced hidden layout and opaque same-session language refresh.
- Both production Release bundles and their final AOT font/icon audits passed.
  Native region tests cover 25 cycles, 96/144/192 DPI and shrinking/growing.
- `desktop_lyric_palette_engine_test` is a separate EXCLUDE_FROM_ALL console
  target using the real Release AOT and production palette window. Neither HWND
  is shown; it does not initialize plugins, audio, stdin or user settings. One
  cold engine and four warm presentations all produced fresh frames, reused the
  same HWND/content and left owner geometry/styles/show events untouched.
- Observed local cold first-engine initialization: 1864.981 ms; warm fresh-frame
  times: 52.870 / 43.739 / 38.522 / 25.574 ms (median 41.130 ms). These are a hidden
  test process's measurements, **not real click-to-visible timing**; its cold
  stage includes the process's first Flutter engine, unlike an already-running
  lyric helper. No absolute speed requirement was weakened or inferred.
- AOT/ICU/assets/Flutter DLL hashes matched before/after the test. Both windows
  stayed hidden; teardown completed with no WM_QUIT. The new test is also in CI,
  independently linked without flutter_assemble, and never packaged.

Logs: `tool/qa-palette-fast-20260830-1711`. These checks do not inspect DWM pixels
or replace real-machine visual acceptance; no installed player was opened.

## Earlier verification (2026-08-30, before warm reuse)

- `desktop_lyric_palette_bridge_test.dart`: **13/13**. Single-flight open,
  100-to-1 slider batching, field merge, current theme/language/font/errors,
  stale sessions, late update failures, creation failure, timeout, final-edit
  acknowledgement, retry, malformed snapshot and disposal.
- Migrated palette lifecycle/locale plus normal legacy layout/taskbar matrix:
  **53/53** (root integration run). Independent panel app, four languages,
  200% text, explicit creation errors, retained color selection and unchanged
  owner geometry on panel open/close. Normal font-driven layout still works.
- Actual helper runner native compilation and link: passed with MSVC
  `/W4 /WX`; no Flutter full build was performed for this diagnostic task.
- Repository native regression:
  `third_party/desktop_lyric/windows/runner/tests/owned_window_test.cpp`, target
  `desktop_lyric_owned_window_test` (**EXCLUDE_FROM_ALL**, not installed):
  **25 hidden real HWND cycles passed**. Bounds and style bits remain unchanged;
  no owner size/move/show changes, no inactive-owner focus theft, no `WM_QUIT`,
  owner destruction also destroys its child. Z-order-only activation messages
  are deliberately not misreported as moves/resizes.

The native regression can be built explicitly from an already configured
helper build with `cmake --build <helper-build> --config Release --target
desktop_lyric_owned_window_test`. Its binary is isolated in
`<helper-build>/palette_tests/Release` rather than the packaged runner directory.
The test links the already-generated Flutter import library through a separate
imported target, without the production `flutter_assemble` dependency. Running
native checks cannot silently regenerate Dart kernels after release auditing.
Add the helper's Flutter ephemeral directory
to the test process DLL search path, then run the resulting console test. It
never calls `ShowWindow`, launches the installed player, captures a screen or
reads/writes user files.

### Verification boundary

These results establish protocol, widget, real HWND geometry/focus and native
compilation contracts. The hidden HWND test does **not** create the second
Flutter engine or inspect DWM output. No installed-player launch, GUI
automation, screenshot or real-machine visual acceptance was performed, per
the user's instruction. The code removes the known parent-resize path; it is
not a claim that the reported visual symptom was observed after the change.
