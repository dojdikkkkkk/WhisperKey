# WhisperKey — instructions for coding agents

You are an agent (Claude Code, Codex, Hermes, OpenClaw, …) whose user asked you to
install, fix, or maintain WhisperKey. This file is your runbook.

## What this is

Offline dictation for macOS: a Swift menu-bar app captures the right-⌘ hotkey and the
microphone, a local Python server (`server/transcribe_server.py`, port 8737) runs MLX
Whisper on the GPU, and the recognized text is delivered into the focused app.
Config: `~/.whisperkey/config.json`. Glossary: `server/glossary.json` (hot-reloaded).

## Installing for your user

1. Check prerequisites: Apple Silicon (`uname -m` → `arm64`), Xcode CLT
   (`xcode-select -p`), `python3`. Anything missing → help the user install it first.
2. Run `./install.sh` (or the steps from README.md manually). Verify each step:
   - `server/venv/bin/python -c "import mlx_whisper"` exits 0;
   - `swift build -c release` completes; `/Applications/WhisperKey.app` exists.
3. Permissions — the #1 source of "it doesn't work":
   - You canNOT grant TCC permissions programmatically. Walk the user through
     System Settings → Privacy & Security → Microphone AND Accessibility.
   - After the Accessibility grant, the app MUST be relaunched.
   - Known trap: the hotkey works WITHOUT Accessibility (modifier monitoring is
     exempt), so "recording glows but no text appears" = missing/stale Accessibility.
   - Known trap: ad-hoc signing resets the grant on every rebuild. Prefer a real
     signing identity (`security find-identity -v -p codesigning`); `build.sh`
     auto-detects one.
   - Cleaning stale duplicate entries: `tccutil reset Accessibility dev.whisperkey.app`.
4. Verify end-to-end without asking the user to speak:
   ```bash
   # server up and model loaded?
   curl -s localhost:8737/health          # {"status":"ok",...}
   # transcription works? (synthesize speech through the speakers is unreliable in CI;
   # prefer a sample wav)
   say -v Milena -o /tmp/wk-test.wav --data-format=LEI16@16000 "проверка диктовки" \
     && curl -s --data-binary @/tmp/wk-test.wav localhost:8737/transcribe
   ```
   (Use the port from config; default 8737.)
5. Check the logs when debugging: `server/server.log`, and `~/.whisperkey/debug.log`
   after setting `"debugLog": true` in the config (then restart the app).

## Setting up glossary self-learning

Ask the user which backend they want, then set `learnBackend` in
`~/.whisperkey/config.json`:

- **You are the user's always-available agent?** Set `"learnBackend": "agent-manual"`.
  The server then writes tasks to `server/learn_request.md`. Whenever the user asks
  you to "teach the dictation dictionary", read that file, do what it says, and merge
  the JSON into `server/glossary.json` (dedup terms, validate each regex compiles,
  keep `terms` under 120 entries). The server hot-reloads the file.
- **Ollama installed** (`ollama --version` works): `"learnBackend": "ollama"`,
  make sure the model is pulled: `ollama pull qwen3:4b`.
- **Claude Code / Codex CLI**: `"learnBackend": "claude"` or `"codex"`.

Seed the glossary from the user's existing texts (with their permission):
`server/seed_glossary.py <paths>` prints candidate terms — curate together with the
user, never dump hundreds of terms (the decoder hint degrades past ~150 words).

## Changing the speech model

Edit `"model"` in `~/.whisperkey/config.json` (any `mlx-community/whisper-*` HF repo),
then `curl -X POST localhost:8737/restart`. Poll `/health` until `"status":"ok"` —
first load downloads the weights.

## Code map (for fixes)

- `Sources/WhisperKey/HotkeyMonitor.swift` — right-⌘ tap/hold state machine
- `Sources/WhisperKey/NotchOverlay.swift` — notch glow animation (NSPanel + SwiftUI)
- `Sources/WhisperKey/TextInserter.swift` — delivery cascade: AX → unicode typing → clipboard.
  macOS quirk: the unicode string must be attached to keyDown ONLY.
- `Sources/WhisperKey/SettingsView.swift` — settings window / setup wizard
- `server/transcribe_server.py` — HTTP API: /health /transcribe /learn /restart
- `server/learn.py` — glossary learning backends
- Build gotcha: with only Command Line Tools, SwiftUI `@State` (a macro in the
  macOS 26+ SDK) fails to compile — this codebase avoids it deliberately
  (TimelineView / ObservableObject instead). Keep it that way or require full Xcode.
