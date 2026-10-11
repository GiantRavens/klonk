# Settings redesign manifest

Input: Klonk 2.4, Hammerspoon Lua, clean tracked source; pre-existing untracked
`ci/` is outside this change. Installed Spoon is a symlink to this checkout.

## Classification and strategy

| Existing control | Destination | Strategy / expected outcome |
| --- | --- | --- |
| Keyboard on, set, recent sets, volume | Sound and motion / Keyboard sounds | Toggle reveals searchable categorized picker, preview, continuous volume |
| Mouse clicks and scrolling | Keyboard / More options | Preserve existing keyboard-dependent audio semantics |
| Ambient on/off, sound, recents, volume | Sound and motion / Ambient sound | Separate remembered choice from off state; explicit preview |
| Desktop on/off, clips, recents | Sound and motion / Live desktop | Searchable, paged still-image gallery; remember disabled choice |
| Speed, rotation, shuffle, battery pause | Live desktop | Speed primary; rotation and battery under More options |
| Add media, sync Aerials, recorded-pack link | Respective card / Library options and Tools | Keep empty libraries actionable |
| Master mute | Window header and menu bar | Preserve all individual settings; silence active voices and previews |
| Presenter, special keys | Tools | Session-only visibility toggle, clear explanation |
| Studio | Tools and menu bar | Existing launch path retained |
| Config-only directories, voice cap, hotkey bindings | General / configuration guidance | Preserve Lua API; no new editable path or code-execution surface |

Implementation: bundled HTML form hosted by a native WKWebView window, validated
message bridge to the existing Lua engine, no settings server or new required
dependency. Optional ffmpeg generates small, on-demand still previews one at a
time; unavailable previews retain a usable text picker. State stays in hs.settings.
The form supports system light/dark appearance, labeled controls, keyboard focus,
reduced-motion CSS, and no automatically playing preview gallery.

## Verification and telemetry contract

- Before each settings operation: validate action/value/catalog membership.
- Emit `settings action=start/finish`, success/failure class, and elapsed time;
  avoid recording typed content or user paths. UI receives acknowledgement or
  an actionable error. Timeout exposes a silent bridge failure.
- Thumbnail failures are reported distinctly from missing media; decoding is
  asynchronous, bounded, and cancelled on close.
- Regression checks: setting retention, invalid inputs, global mute, preview
  cleanup, empty libraries, flat menu and existing Presenter tests.
- Live checks: open window, render each section, perform and restore settings,
  check bridge acknowledgement and missing-media behavior, inspect screenshots.

Design references: Apple HIG Settings, Menus, Accessibility; Hammerspoon
hs.webview and hs.webview.usercontent documentation. This is a web form inside
a native window, not a SwiftUI rewrite.

## Outcome (2026-09-26)

Implemented the three experience cards and a Tools tab; omitted an empty General
page because Klonk has no separate runtime preferences to put there. Existing
Lua configuration remains available and the new `settings` hotkey is optional.

Verification: 46 state-contract checks and 9 Presenter regressions passed; 20
live WKWebView control checks passed with starting preferences restored. Real
NSSound playback was separately confirmed with `isPlaying()` at zero test volume.
Window close/reopen cleanup and thumbnail generation verified in Hammerspoon.

User feedback incorporated: opaque unified title area (native webview windows
start with a clear NSWindow background); muted preview buttons now explicitly
say **Unmute and try**, then **Stop preview**. The action intentionally unmutes
global audio; simply opening Settings never changes mute state.

Integration lessons: hs.task stdout is text, so pass image output through a
short-lived binary file; clean it on success, failure, or close. This Hammerspoon
build supplies `{code=0}` on successful JavaScript evaluation: test the code,
not the table's truthiness. Desktop previews are decoded one at a time and cache
by file modification time. No server dependency was added. Source changes are
uncommitted; the pre-existing ci directory was left untouched.
