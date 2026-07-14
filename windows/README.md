# WhisperKey for Windows — roadmap

Not built yet. Architecture notes for the port:

- **Tray app** (C# / WinUI or Python + pystray) instead of the menu bar app.
- **Hotkey**: right-Ctrl or right-Win via `RegisterHotKey` / low-level keyboard hook
  (`WH_KEYBOARD_LL`) — modifier-only hotkeys need the hook, same tap/hold state
  machine as `HotkeyMonitor.swift`.
- **STT backend**: the same HTTP server contract (`/health`, `/transcribe`, `/learn`,
  `/restart`), but `faster-whisper` (CTranslate2) with CUDA when available, CPU
  int8 otherwise — MLX is Apple-only.
- **Text delivery**: `SendInput` with `KEYEVENTF_UNICODE` (the Windows twin of the
  unicode-typing strategy), UI Automation `ValuePattern` as the AX-equivalent.
- **Indicator**: borderless always-on-top layered window, top-center — the "virtual
  notch" mode already designed for external displays.

The glossary format, learning backends (`server/learn.py`), and config schema are
platform-independent and will be reused as-is.

Contributions welcome — open an issue if you want to take this.
