# Hidden playback visuals: lifecycle QA

Scope: keep playback, lyric reading, mounted layout and artwork caches intact.
The interface setting **不可见时暂停视觉更新 / Pause visual updates when hidden**
defaults to on and is persisted independently as
`Rendering: {"pauseWhenHidden": true}`. Missing or malformed legacy fields use
the same default. Saving the choice does not query or save transient window
geometry; a failed save leaves the session choice usable and offers a retry.

## Findings and changes

- The now-playing route is already lazy and uses `maintainState: false`.
  Its full lyric view is not constructed before entering that route. Compact
  layouts likewise construct the lyric surface only in the lyric layout.
- The mounted vertical lyric surface previously kept its position subscription
  until disposal. It now detaches on a covered route, disabled `TickerMode`,
  paused application, or native hidden-window notification. It also cancels
  pending follow/manual-scroll work and settles decorative row transitions.
  Returning reads the current position once and follows immediately; it does
  not replay hidden samples or discard the existing row state/layout.
- The full-width spectrum already checked route, lifecycle and motion policy.
  It now also detaches immediately when the native window is hidden, without
  waiting for a Flutter frame or lifecycle notification. The BASS producer
  computes frequency FFT only while its stream has listeners, so this removes
  the hidden view's demand without disabling any other visible consumer.
- Background image motion already cancels its low-frequency timer for hidden
  windows, inactive routes, paused applications and reduced motion. Its
  existing behavior and artwork cache were retained.

## Optional continued updates for mounted views

Turning the preference off bypasses **visibility-only** gates for the mounted
vertical lyric position subscription, frequency-spectrum subscription and
20-Hz background timer. Native hide/minimize, a covered route, and the normal
page retained behind mini mode no longer stop those data/timer owners. The
top-level native-hidden and mini-mode `TickerMode` gates, and visited settings
sections' ticker gates, also respect the preference. Hidden input/focus remains
blocked. Preference/notifier changes update subscriptions and timers directly,
without requiring the hidden HWND to paint another Flutter frame.

This does not prebuild the mini view, unvisited settings sections or unopened
now-playing routes; it does not change `maintainState`, route disposal, audio
playback, lyric parsing, image caches or source loading. It can increase
background work, including FFT demand. Real `paused` and `detached` lifecycle
states always stop these visual stream/timer owners. Existing platform and
MediaQuery reduced-animation/high-contrast policies remain in force rather
than being interpreted as visibility. For example, high contrast still stops
decorative background motion; it does not newly disable spectrum data or
current lyric text, whose existing policies are unchanged.

The guarantee is continued **mounted visual data and timer updates**, not
forced offscreen rasterization. Flutter's Navigator may still mute animation
tickers in an offstage route, and the platform may stop producing frames while
hidden or paused. We do not override those framework/scheduler mechanisms.

This is subscription/lifecycle verification, not a claim of a measured CPU or
memory percentage improvement. Playback services, background lyric reading,
top-bar lyrics and desktop lyrics were deliberately left unchanged.

## Verification

The original default-on verification passed **82/82** in five focused suites:

```text
hidden_rendering_lifecycle_test.dart
vertical_lyric_view_test.dart
lyric_spring_test.dart
full_width_spectrum_test.dart
background_image_motion_test.dart
```

The six new lifecycle cases cover initial hidden mounting, 500 ignored hidden
position/spectrum samples, native hide before another frame, covered routes,
application pause/resume, source/notifier replacement, disposal, and retained
lyric `State` with a fresh position on return. Existing suites cover motion
reduction, active transition interruption, scrolling, large text and spectrum
interaction. No GUI, user media, user settings or saved library was accessed.

The preference regression suites passed **24/24**:

```text
rendering_preferences_test.dart
rendering_preferences_persistence_test.dart
rendering_visibility_lifecycle_test.dart
rendering_visibility_hosts_test.dart
```

They exercise both disk round trips in a workspace-only fixture, legacy/default
loading, failed saves and retry, all four UI languages at 320px/200% text,
immediate hidden subscribe/unsubscribe on a live setting change, covered-route
data/timers, hard pause/detach, reduced-motion/high-contrast behavior, listener
replacement and disposal. Real retained widget/ticker tests cover the native
visibility host, mini-mode parent gate and lazily visited settings sections.
No CPU/RAM percentage or actual hidden-HWND frame rate is claimed.

The five original suites above plus `app_window_mode_host_test.dart`,
`grouped_settings_test.dart` and `ui_language_test.dart` were rerun after the
preference change: **127/127 passed**, for **151/151** in this verification.
Workspace logs: `build/rendering-preferences-tests.log` and
`build/rendering-existing-tests.log`. Test disk writes were confined to temporary
directories under `build/test-data`; actual user settings and media were not
read or written.
