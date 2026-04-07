# Coordify

> **[日本語版はこちら](README.ja.md)**

An AltTab-like Space switcher for macOS. Press **Option+Tab** to see a visual overlay of all your Spaces and switch between them instantly.

Coordify runs as a menu bar agent (no Dock icon) and relies on [yabai](https://github.com/koekeishiya/yabai) for querying Space information.

## Features

- **Option+Tab overlay** — a dark, translucent HUD panel showing live thumbnails of every Space
- **Two interaction modes** — transient mode (hold Option, tap Tab to cycle, release to confirm) and pinned mode (tap Option+Tab once to lock the panel open for browsing)
- **Fullscreen app support** — native fullscreen apps appear alongside regular desktop Spaces, each with a single-letter shortcut
- **Multi-display awareness** — automatically detects multiple displays and groups Spaces per display; remembers the layout even after a monitor is disconnected
- **Rich Space cards** — each card shows a window thumbnail composited on the desktop wallpaper, the Space name, a shortcut key badge, and a list of running apps (expandable on selection)
- **Keyboard, mouse, and number-key navigation** — full control via Tab, Shift+Tab, arrow keys, number keys (1–0), letter shortcuts for fullscreen apps, Enter, Escape, and mouse click

## Requirements

- macOS 13.0+
- [yabai](https://github.com/koekeishiya/yabai) (SIP-disabled scripting addition is **not** required)
- [Taskfile](https://taskfile.dev/) (for building)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [SwiftLint](https://github.com/realm/SwiftLint) & [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) (for linting)

## Setup

### 1. Grant permissions

On first launch Coordify will ask for two macOS permissions:

- **Accessibility** — required for the global Option+Tab hotkey. Without it the app cannot intercept keyboard events.
- **Screen Recording** — required for capturing Space thumbnails via ScreenCaptureKit. The app works without it but thumbnails will be blank.

### 2. Enable Mission Control shortcuts

Coordify switches Spaces by simulating the built-in **Ctrl+Number** keyboard shortcuts. These must be enabled in macOS:

1. Open **System Settings > Keyboard > Keyboard Shortcuts > Mission Control**.
2. Enable **"Switch to Desktop 1"** through **"Switch to Desktop N"** for every Space you use.

If the shortcuts are disabled at launch, Coordify shows a setup guide panel with step-by-step instructions.

## Build & Run

```bash
task build      # generate Xcode project + build
task generate   # regenerate Coordify.xcodeproj from project.yml
task lint        # SwiftLint (strict) + SwiftFormat --lint
task format      # SwiftFormat auto-fix
task clean       # clean build artifacts
```

## Usage

### Opening the switcher

Press **Option+Tab** to open the overlay. What happens next depends on how you continue:

#### Transient mode (hold Option)

Hold **Option** down and tap **Tab** repeatedly to cycle forward through Spaces (add **Shift** to go backward). When you release **Option**, the currently highlighted Space is activated. This is the fastest way to switch — similar to the standard macOS Cmd+Tab app switcher.

#### Pinned mode (tap and release)

Press **Option+Tab** and release both keys immediately. The panel stays open ("pinned") and you can browse freely:

| Input | Action |
|---|---|
| **Left / Right arrow** | Move selection horizontally |
| **Up / Down arrow** | Move selection between rows |
| **Scroll up / down** | Same as Up / Down arrow keys |
| **Tab / Shift+Tab** | Move forward / backward through the list; at either edge, wraps to the adjacent display (multi-display) |
| **Number key (1–0)** | Jump directly to the Space with that shortcut number |
| **Letter key** | Jump to the fullscreen app whose shortcut matches that letter |
| **Enter** | Confirm the current selection and switch |
| **Click on a card** | Select and switch to that Space |
| **Escape** | Cancel — close the panel and return focus to the previously active app |
| **Click outside the panel** | Same as Escape |
| **Space bar** | Cycle to the next display's Space group (multi-display) |
| **Right-click a card** | Reassign the Space to the next display in the mapping |
| **Cmd+,** | Open the display mapping JSON file for manual editing |

### What the Space cards show

Each card in the grid displays:

- **Thumbnail** — a screenshot of the Space's windows composited on the wallpaper. For fullscreen apps the window image is shown directly.
- **Space name** — "Desktop 1", "Desktop 2", etc. for regular Spaces; the app name for fullscreen Spaces.
- **Shortcut badge** — a number (1–0) for regular Spaces, a letter (A–Z) for fullscreen apps, or "ESC" for the currently focused Space.
- **App list** — icons and names of running apps in that Space (up to 3 by default; all shown when the card is selected). Shows "no apps" if the Space is empty.
- **Visual indicators** — the focused Space has a brighter background; the selected card has an accent-colored border; hovered cards show a subtle highlight.

### Fullscreen apps

Native fullscreen apps (e.g. Safari in fullscreen) are listed alongside regular desktop Spaces. They are switched to by activating the app process directly rather than via Ctrl+Number. Each fullscreen app is automatically assigned a single-letter shortcut based on its name.

### Multi-display support

When two or more displays are connected, Coordify groups Spaces by display. The footer of the panel shows the current display name (e.g. "Built-in Retina Display", "DELL U2723QE"). Press **Space bar** in pinned mode to cycle through displays.

**Display mapping persistence** — when you have multiple displays connected, Coordify saves the Space-to-display assignment to `~/Library/Application Support/Coordify/display-mapping.json`. If you later disconnect a display, the saved mapping is used to keep Spaces organized by their original display. The disconnected display's name is shown with a grayed-out "(disconnected)" suffix.

**Automatic backups** — every time the mapping is saved, a backup copy is written to `~/Library/Application Support/Coordify/backups/`. Backup files are named after the connected display names and a short hash of the display UUIDs (e.g. `Built-in Retina Display_DELL U2723QE-a3f1c9b2.json`). Each display configuration keeps exactly one backup, overwritten on every save, so you always have the latest mapping per setup.

You can right-click a Space card to reassign it to a different display in the mapping, or press **Cmd+,** to open the JSON file directly.

### Menu bar

Coordify lives in the menu bar with a small grid icon. The menu shows:

- The name of the currently focused Space
- A warning if yabai is not found
- A link to open the display mapping file
- A link to the Accessibility permission settings
- Quit

## Architecture

```
Coordify/
├── Core/
│   ├── SpaceManager        — queries yabai, resolves app info per Space
│   ├── HotkeyInterceptor   — CGEventTap for Option+Tab detection
│   ├── WorkspaceObserver    — listens to Space change notifications
│   └── ThumbnailCache      — ScreenCaptureKit-based screenshot capture
├── UI/
│   ├── SwitcherPanel        — the overlay NSPanel (transient + pinned modes)
│   ├── SpaceCardView        — individual Space card with thumbnail and app icons
│   └── MenuBarController    — menu bar status item
├── Adapters/
│   ├── YabaiClient          — async yabai CLI wrapper
│   ├── DisplayMappingAdapter — multi-display Space assignment persistence
│   └── ...
└── Models/
    ├── SpaceInfo
    ├── DisplayMapping
    └── ...
```

## License

[MIT License](LICENSE)
