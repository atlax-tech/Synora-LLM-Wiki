# P0-04 TextKit 2 feasibility

Status: `CHANGES_REQUIRED` for the full exit gate; the TextKit 2 probe and Unicode range-checking fixture compile, while runtime fixture observation plus real IME, attachment, undo/redo, VoiceOver and latency measurements remain `NOT_RUN`.

The P0 probe uses `NSTextView(usingTextLayoutManager: true)` through a small `NSViewRepresentable`. Its fixture contains Chinese, English, a combining mark, a ZWJ emoji and line boundaries. The fixture checks UTF-16 ranges stay ordered and inside the source string. The probe host exposes the editor and a range status in its engineering-only window.

Evidence:

- `xcodebuild -project SynoraWiki.xcodeproj -scheme SynoraP0Probes -configuration Debug -destination 'platform=macOS,arch=arm64' ... build` → exit `0`.
- The build proves the probe host compiles; it does not execute the range fixture. An automated XCTest for real marked-text input is intentionally not claimed because it would not prove an actual third-party IME session.

Remaining work before P0 exit: run system and WeChat IME scenarios, attachment copy/paste and undo/redo, keyboard/VoiceOver traversal, and signpost measurements for the 100k-character fixture. No TextKit 1 fallback is selected without a reproducible TextKit 2 failure.
