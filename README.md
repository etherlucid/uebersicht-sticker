# Animated Sticker & Cutout Studio Widget for Übersicht

A hardware-accelerated animated desktop sticker manager and background cutout studio for [Übersicht](https://tracesof.net/uebersicht/) on macOS. Place multiple animated GIFs, WebPs, or PNGs anywhere across multiple displays, sync animation playback to real-time system audio, and remove backgrounds using Apple Vision AI or color-key chroma cutout.

---

## ✨ Features

- **Multi-Instance Desktop Stickers**: Place as many animated or static stickers as you want across any connected display.
- **Sprite Sheet Canvas Engine (`sheet_generator.py`)**: Automatically converts animated GIFs and WebPs into cached WebP sprite sheets (`*_sheet.webp` + `*_meta.json`), allowing instant frame-accurate pausing, resuming, and Retina-sharp rendering on a hardware-accelerated HTML5 `<canvas>`.
- **Built-In Sticker Manager & Cutout Studio (`StickerManager.app` / `menu_helper.swift`)**:
  - **Sticker Library Grid**: Browse, preview, place, duplicate, or delete stickers in your library.
  - **Background Cutout Studio**: Remove backgrounds from static or animated stickers using **Smart AI Subject Lifting** (`VNGenerateForegroundInstanceMaskRequest` on macOS 14+) or **Color-Key Chroma Cutout** with eyedropper sampling, tolerance, and edge feathering.
- **🎵 Real-Time Audio Sync (`audio_check.c`)**:
  - Uses a lightweight CoreAudio loopback tap (`audio_check`) to measure live system audio RMS levels.
  - Animates stickers in rhythm when music or video plays and freezes them cleanly mid-frame when audio stops, with configurable sensitivity presets (`Very High` to `Low` or custom `1–100`).
- **Multi-Monitor Drag & Drop (`lib/desktop.js`)**:
  - Drag stickers smoothly across monitor bezels with a live cross-screen ghost preview, or move stickers directly via the right-click **Display** submenu.
  - Refined edge snapping with modifier-key bypass (`Cmd`, `Option`, or `Shift`).
  - Shared z-index layer ordering (`Bring to Front`, `Bring Forward`, `Send Backward`, `Send to Back`) across companion Übersicht widgets.

---

## 🚀 Installation

1. Copy or clone `sticker.widget` into your Übersicht widgets folder:
   ```bash
   cp -R sticker.widget "$HOME/Library/Application Support/Übersicht/widgets/"
   ```
2. Compile the native helpers (if modifying from source):
   ```bash
   cd "$HOME/Library/Application Support/Übersicht/widgets/sticker.widget"
   swiftc -O menu_helper.swift -o menu_helper
   cp menu_helper StickerManager.app/Contents/MacOS/menu_helper
   clang -O3 audio_check.c -framework CoreAudio -framework AudioToolbox -o audio_check
   ```
3. Refresh Übersicht:
   ```bash
   osascript -e 'tell application id "tracesOf.Uebersicht" to refresh'
   ```

---

## 🎮 Controls

| Action | Result |
| :--- | :--- |
| **Click `+` Placeholder** | Quick-select a sticker or open Sticker Manager |
| **Click & Drag** | Reposition sticker (or drag across monitor edges to switch displays) |
| **Cmd / Option / Shift + Drag** | Free drag with edge snapping bypassed |
| **Double-Click** | Flip horizontal direction (Face Left / Face Right) |
| **Right-Click** | Open native macOS context menu (Sticker Library, Cutout Studio, Audio Sync, Scale, Opacity, Display, Order) |

---

## 🔗 Companion Widgets

Part of the [`etherlucid`](https://github.com/etherlucid) Übersicht desktop suite:
- [`uebersicht-now-playing`](https://github.com/etherlucid/uebersicht-now-playing) — MediaRemote & YouTube Music Now Playing widget
- [`uebersicht-cava`](https://github.com/etherlucid/uebersicht-cava) — Real-time 60fps CAVA audio spectrum visualizer
- [`uebersicht-shell`](https://github.com/etherlucid/uebersicht-shell) — Pinned command monitor & ANSI terminal output widget
- [`uebersicht-sticker`](https://github.com/etherlucid/uebersicht-sticker) — Animated desktop sticker manager & Vision AI cutout studio

---

## 📄 License

MIT License.
