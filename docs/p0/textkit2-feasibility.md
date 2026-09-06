# P0-04 TextKit 2 feasibility

Status: `ACCEPTED FOR P0 DIRECTION`; production editor validation is transferred to P2. The TextKit 2 probe and Unicode range-checking fixture compile, and the ordinary application window UI test passes. The probe editor/action UI test was run twice after process cleanup but the system reported that `tech.atlax.SynoraWiki.P0Probes` had not loaded accessibility; this is retained as an environment-limited result, not treated as a product success.

The P0 probe uses `NSTextView(usingTextLayoutManager: true)` through a small `NSViewRepresentable`. Its fixture contains Chinese, English, a combining mark, a ZWJ emoji and line boundaries. The fixture includes code to check that UTF-16 ranges stay ordered and inside the source string. The probe host exposes the editor, range status and attachment action in its engineering-only window.

Evidence at closure HEAD `ce4a71c`:

- `xcodebuild -workspace SynoraWiki.xcworkspace -scheme SynoraP0Probes -configuration Debug -destination 'platform=macOS,arch=arm64' ... build` → exit `0`.
- `testApplicationLaunchesWithWindow` → `PASS`.
- `testProbeLaunchesWithAccessibleEditorAndAttachmentAction` → system-level `Application 'tech.atlax.SynoraWiki.P0Probes' has not loaded accessibility` on two attempts; no claim is made for the runtime editor action path.

TextKit 2 remains the accepted direction. Real system/WeChat IME scenarios, attachment copy/paste and undo/redo, keyboard/VoiceOver traversal, and signpost measurements for the 100k-character fixture are P2 production validation. No TextKit 1 fallback is selected without a reproducible TextKit 2 failure.
