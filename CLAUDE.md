# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

All commands use [Task](https://taskfile.dev/). Shared tasks are in `Taskfile.dist.yml`.

```bash
task build      # xcodegen generate + xcodebuild (generate is skipped if project.yml unchanged)
task generate   # Regenerate Coordify.xcodeproj from project.yml
task lint       # SwiftLint (strict) + SwiftFormat --lint
task format     # SwiftFormat auto-fix
task clean      # xcodebuild clean + remove DerivedData
```

`Taskfile.yml` is gitignored for personal tasks (e.g. `task deploy` for kill/build/launch cycle).

Build requires `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (set in Taskfile).

## Project Configuration

- **XcodeGen** generates the Xcode project from `project.yml` — edit `project.yml`, not the xcodeproj directly
- Bundle ID: `net.yuuan.Coordify`, Team: `BWK37MJZ59`
- macOS 13.0+, Swift 5.9+
- `LSUIElement = true` (menu bar agent app, no Dock icon)
- SwiftLint: trailing_comma disabled (`.swiftlint.yml`), SwiftFormat pinned to Swift 5.9 (`.swiftformat`)

## Architecture

Coordify is a macOS menu bar app that provides an AltTab-like overlay for switching between Spaces. It depends on **yabai** for querying space information and uses keyboard shortcut simulation (Ctrl+number) for switching since yabai's `space --focus` requires SIP-disabled scripting addition.

### Startup flow (CoordifyApp.swift)

`@main AppDelegate` with explicit `static func main()` — needed because there's no NIB, so `NSApplicationMain` won't set the delegate automatically. The launch sequence: permission checks (Accessibility, Screen Recording, Mission Control shortcuts) → ConfigStore → SpaceManager.refresh → WorkspaceObserver → HotkeyInterceptor → MenuBarController.

### Core layer

- **YabaiClient** — Async wrapper around yabai CLI. Resolves binary path at init (`/opt/homebrew/bin` → `/usr/local/bin` → `which`). `focusSpace` falls back to `CGEvent` Ctrl+number simulation when scripting addition is unavailable.
- **SpaceManager** — `@MainActor` singleton. Calls yabai to get spaces, resolves app info per space via `CGWindowListCopyWindowInfo` + `NSRunningApplication`. For fullscreen spaces, triggers app-specific screenshot capture.
- **ThumbnailCache** — ScreenCaptureKit captures. macOS 14+ uses `SCScreenshotManager`, macOS 13 falls back to `SCStream`. Captures happen only at two points: when the switcher opens and before a space switch executes (not on `spaceDidChange`) to avoid race conditions with yabai state lag.
- **HotkeyInterceptor** — `CGEventTap` at session level. Detects Option+Tab/Shift+Tab/arrows/Escape. Delegates to AppDelegate via `@MainActor` protocol. The C callback bridges to the Swift class via `Unmanaged` pointer.
- **WorkspaceObserver** — Listens to `activeSpaceDidChangeNotification`. Only refreshes space list; does NOT capture screenshots (to avoid UUID mismatch from yabai timing lag).

### UI layer

- **SwitcherPanel** — `NSPanel` with `.nonactivatingPanel, .borderless, .hudWindow` styles and `.canJoinAllSpaces`. Has two modes: transient (closes on Option release) and **pinned** (stays open after single Alt+Tab, accepts arrow/Enter/Escape/number keys and mouse clicks via local event monitor).
- **SpaceCardView** — NSView showing thumbnail, space name, and app icon list. Fullscreen spaces show their app name instead of "Desktop N". Active/selected spaces use white text; inactive uses 50% white.

### Key behavioral details

- **Pinned mode**: Single Alt+Tab opens and pins the panel. Subsequent Alt+Tab navigates without confirming. Enter/number keys/click confirm. Escape/click-outside cancels and restores focus to the previously active app.
- **Fullscreen apps**: Included in the switcher alongside regular spaces. Switching to them uses `NSRunningApplication.activate()` instead of Ctrl+number.
- **Mission Control shortcut check**: Reads `com.apple.symbolichotkeys` UserDefaults keys 118-127. Counts only non-fullscreen spaces from yabai. Shows a floating guide panel with setup instructions if shortcuts are disabled.
- **Screenshot timing**: Captures only when the switcher opens (current space) and in `commitAndClose` (leaving space, after panel closes but before switch). This avoids the race condition where `spaceDidChange` fires before yabai updates `hasFocus`.

## Spec Reference

`SPEC.md` contains the full development spec. Current implementation covers Phase 1 (MVP). Phase 2 (space naming, app pinning) and Phase 3 (multi-display layout) are not yet implemented.
