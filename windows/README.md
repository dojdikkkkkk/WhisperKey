# WhisperKey for Windows

Native-feeling, local-first dictation for Windows 10/11. It mirrors the macOS
WhisperKey interaction:

- hold **right Ctrl** to talk, then release to transcribe;
- tap **right Ctrl** to start a longer recording, tap again to finish;
- normal right-Ctrl shortcuts are ignored by dictation;
- text is typed into the window that was focused when recording started;
- a top-centre island shows recording, transcription, and completion states.

The hotkey can be changed to right-Win in Settings. Local recognition uses
[`faster-whisper`](https://github.com/SYSTRAN/faster-whisper): CUDA/float16 is
selected automatically when a compatible NVIDIA GPU is available, otherwise
CPU/int8 is used. The first local dictation downloads the selected model.

## Install

Download `WhisperKey-Windows-x64.zip` from the Windows release, extract it, and
run `WhisperKey.exe`. On first launch:

1. Choose the local model (`small` is the balanced default).
2. Allow microphone access if Windows asks.
3. Save Settings. WhisperKey stays in the system tray.

Windows may show a SmartScreen warning for unsigned community builds. Choose
**More info → Run anyway** only when the file came from the official repository.

Configuration, logs, glossary, and dictation history live in
`%USERPROFILE%\.whisperkey`. Cloud API credentials are stored in Windows
Credential Manager and never written to `config.json`.

## Build locally

Python 3.11 or 3.12 is required:

```powershell
cd windows
.\build.ps1
```

The portable distribution is written to `windows\dist\WhisperKey`.

Run tests:

```powershell
$env:PYTHONPATH = "$PWD\app"
python -m unittest discover -s tests -v
```

## Architecture

```text
right Ctrl ──▶ keyboard hook ──▶ WAV recorder
                                    │
                                    ▼
                            localhost:8737
                          faster-whisper/cloud
                                    │
                                    ▼
                       SendInput(KEYEVENTF_UNICODE)
```

The executable starts a second copy of itself with `--server`, preserving the
same local HTTP contract as the macOS implementation: `GET /health` and
`POST /transcribe`.
