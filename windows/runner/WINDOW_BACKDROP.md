# Native window backdrop

When a scene selects `desktop`, it uses the OS compositor's **background** Acrylic/blur. No album
artwork, wallpaper read, desktop screenshot, screen-capture API or simulated
desktop texture participates in this implementation. Opaque Dart content still
covers this backdrop normally, including the album-based detailed player page.

## Channel contract and initialization

Channel: `dan_player/window_backdrop`, standard method codec.

Call `configure({dark: bool, enabled: bool})` only **after** awaiting window_manager's initial
`waitUntilReadyToShow` with `backgroundColor: Colors.transparent`. Its Windows
`SetBackgroundColor` otherwise replaces the AccentPolicy with a plain gradient.
Later brightness or effective native-glass preference changes call `configure`
again; do not reset the background color. `enabled` defaults to true for older
callers. If no main/lyrics/mini profile uses desktop glass, it is disabled. If
any does, its policy stays installed across navigation and mini transitions;
opaque artwork/solid scenes cover it without cycling DWM on every page change.

The method returns a map with:

- `available`: whether a composited background effect was enabled.
- `effect`: `acrylic`, `blur`, or `solid`.
- `dark`: the requested theme, to reject stale Dart responses/events.
- `enabled`: the requested native-glass preference, also used to reject stale replies.
- `fallbackColor`: opaque ARGB integer (64-bit standard-codec integer).
- `reason`: present on `solid`, with a stable reason such as `high_contrast`,
  `transparency_disabled`, `settings_unavailable`, `composition_unavailable`,
  `alpha_surface_unavailable`, `energy_saver`, `disabled`, or `native_effect_unavailable`.

The native side sends `stateChanged` with the same map after relevant system
changes, but only if the reported state actually changes. Frame restoration and
effect selection are separate, posted and coalesced operations. Style/fullscreen
changes repair the frame without resetting an unchanged effect; ordinary move,
resize and `WM_EXITSIZEMOVE` messages do not request any backdrop work. Actual
compositor/display changes can reapply the effect. Invalid arguments return a method error
without changing the window. Unsupported methods return NotImplemented.

A transient native-effect failure can be retried on a real activation or an
explicit configure call. Style/theme messages produced by a fallback must not
create a retry loop, and a policy-disabled backdrop is not a native failure.

## Transparency path

Flutter 3.47.1's Windows ANGLE configuration requests an 8-bit alpha channel and
the Flutter child window does not have a GDI background brush. The native
controller also checks `FlutterEngine::GetGraphicsAdapter`; an unavailable
composited surface is not reported as a working transparent window.

The top-level runner uses `BLACK_BRUSH`, as required for DWM's zero-RGB/zero-alpha
glass backing. It must not return to the old opaque warm/light startup brush.
The controller uses a separate fallback brush only when a solid backdrop is
selected. Dart leaves the desired glass regions translucent; an opaque Scaffold
would entirely obscure this OS backdrop. The shared chrome uses the single
neutral veil described below, not an opaque fill or another blur filter.
The parent has `WS_CLIPCHILDREN`, so its GDI background erase cannot paint over
the live Flutter child. Only exposed parent pixels/resize gaps are cleared.
There is no `RedrawWindow(RDW_ERASE | RDW_ALLCHILDREN)` after a move or material
update: DWM presents its material and Flutter owns repainting its own surface.

The actual API order is:

1. Try `DWMWA_SYSTEMBACKDROP_TYPE = DWMSBT_TRANSIENTWINDOW` and check its HRESULT,
   then extend glass over the client area. This corresponds to Desktop Acrylic
   on current Windows 11, not the wallpaper-only Mica material.
2. If unsupported, dynamically resolve `SetWindowCompositionAttribute` and use
   `ACCENT_ENABLE_BLURBEHIND` (3). Legacy Acrylic (4) is deliberately never
   enabled: it has a known Windows 10 title-drag performance problem. The same
   blur stays active before, during and after dragging, without a transition
   through a disabled/black frame. This Windows 10/early Windows 11 path is an
   undocumented OS ABI; its return value is checked.
3. If unavailable or prohibited by accessibility/personalization/power settings,
   turn off blur and use an opaque neutral background. High contrast uses the
   user's `COLOR_WINDOW`; Windows settings are read but never changed.

The legacy/solid paths use zero DWM glass margins. The former one-pixel top
extension exposed a white line; native AccentPolicy blur does not require it.
This can remove Windows 10's external DWM shadow, but does not affect the content
panel's Flutter shadow. The modern backend retains its full-client extension.
`DWMWA_BORDER_COLOR = DWMWA_COLOR_NONE` is probed separately so early Windows 11
can suppress its native border even without the newer Desktop Acrylic API.
Windows 10 may reject that optional attribute; this does not disable blur.
Except for GDI child clipping, sizing styles are unchanged. No resize hit-test or
non-client geometry changes are needed, preserving the existing Win10 three-edge
fix and the title capsule's equal top/bottom spacing.

## Stronger frosted appearance

By default, `AppBackdrop` draws one neutral, approximately 70% opaque veil over the native
material (`0xB3F3F3F3` in light mode, `0xB3202020` in dark mode). This reduces the
contrast and colour strength of busy windows behind the player, leaving about
30% of the native material's changing pixels visible. The same full-window
layer backs the title bar, persistent navigation and exposed bottom/right
margins; none of those areas gets its own tint or filter. It ignores pointer and
semantics input. The background settings independently select solid/desktop/
artwork for the main window, lyric player and mini player. Their transparency
sliders only adjust each background veil, never content opacity. The main
content panel remains opaque. Mini defaults to a more legible 78% veil with
an opaque themed fallback when native glass is unavailable.

This is an obscuration/legibility adjustment, **not an adjustable native blur
radius**. `DWMWA_SYSTEMBACKDROP_TYPE` selects a Windows material; it does not
expose a blur-radius parameter. The legacy AccentPolicy path also provides no
supported cross-version radius setting. Raising a Flutter `BackdropFilter`
radius would only filter this app's own scene, not the windows behind it. The
implementation therefore adds neither a second filter nor screen capture, and
does not switch back to legacy Acrylic (4).

The desktop veil is independent of the album palette. It changes only with
light/dark theme or its transparency preference, has no transition/ticker, and requires no extra native configure/frame/
erase calls. All drag/resize policies, zero legacy margins and child clipping
remain unchanged. When effects are unavailable, transparency is disabled or
high contrast is active, the whole veil is replaced by the existing opaque
neutral/system-colour fallback rather than blended on top of it.

Artwork scenes instead use a cached, bounded 512-pixel source request behind
one `ImageFiltered` layer, with adjustable 8–100 logical-pixel blur and a
readability veil. Those source and radius changes are Dart-only. High contrast
skips artwork loading/filtering. Foreground covers retain the independent
DPR-aware artwork pipeline and are never filtered through the background.

## Verification and limits

`tests/window_backdrop_policy_test.cpp` is an independent C++17 test executable
with no Flutter/Win32 dependency. It checks modern-to-legacy-blur fallback order and
that disabled transparency, high contrast and other safety conditions never
invoke an effect callback. CI builds the `window_backdrop_policy_test` target
after the release build and runs it from `build/windows/x64/backdrop_tests/Release`.
This `EXCLUDE_FROM_ALL` target is deliberately outside the shipping GUI/payload.
It can also be compiled separately with a C++17 compiler.
`tests/window_backdrop_updates_test.cpp` checks the production message policy:
500 drag loops and 500 ordinary resize loops schedule no work, frame-only
repairs preserve effects, queued upgrades are not lost, and composition changes
reapply the material. Its separate `window_backdrop_updates_test` target is also
excluded from the shipped GUI/payload and runs in CI.

Flutter backdrop tests render synthetic colours behind the actual chrome to
check the veil's approximately 70% contrast attenuation, continued response to
changing colours, title/sidebar/margin equality, opaque content preservation,
theme/palette independence and pointer pass-through. These are component alpha
and interaction tests, not screenshots or observations of the Windows desktop.

Successful native API calls and policy tests are **not a visual compositor
test**. Windows 10 and Windows 11 require separate manual/authorized visual
checks, including a different window moving behind the translucent sidebar,
theme changes, system transparency/high contrast, maximize/restore/fullscreen,
and all eight resize directions. The legacy-blur choice avoids the documented
Win10 Acrylic-specific drag path, but does not guarantee a particular frame rate
on every GPU/driver. Do not claim Windows 11 has been visually tested from a
Windows 10-only machine. DWM may also substitute a solid material when the app
is inactive or due to system/GPU policy even after an API request succeeds.

## Primary references

- Microsoft [DWM_SYSTEMBACKDROP_TYPE](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwm_systembackdrop_type)
  (public modern API, Windows 11 build 22621+).
- Microsoft [Acrylic material](https://learn.microsoft.com/en-us/windows/apps/design/style/acrylic)
  (background windows, accessibility/power/inactive behavior).
- Microsoft [Custom Window Frame Using DWM](https://learn.microsoft.com/en-us/windows/win32/dwm/customframe)
  (alpha-zero backing brush and preserving custom frame behavior).
- Microsoft [DwmExtendFrameIntoClientArea](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/nf-dwmapi-dwmextendframeintoclientarea)
  (glass extension and composition change handling).
- Microsoft [DWM window attributes](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute)
  (Windows 11 border-colour capability and `DWMWA_COLOR_NONE`).
- Microsoft [Child Window Update Region](https://learn.microsoft.com/en-us/windows/win32/gdi/child-window-update-region)
  and [RedrawWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-redrawwindow)
  (GDI child clipping and the risks of explicit background erasure).
- Microsoft [High contrast parameter](https://learn.microsoft.com/en-us/windows/win32/winauto/high-contrast-parameter).
- Flutter [3.47.1 ANGLE configuration](https://github.com/flutter/flutter/blob/3.47.1/engine/src/flutter/shell/platform/windows/egl/manager.cc)
  and [Flutter child window](https://github.com/flutter/flutter/blob/3.47.1/engine/src/flutter/shell/platform/windows/flutter_window.cc).
- [flutter_acrylic upstream](https://github.com/alexmercerind/flutter_acrylic)
  (legacy AccentPolicy compatibility and custom-frame shadow behavior); this
  runner's channel/lifecycle/fallback implementation is independent code.
