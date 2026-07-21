# WhisperKey

**Offline dictation for macOS, triggered by the right ⌘ key.** Speak in any app — the text appears at your cursor ~2 seconds later. Runs entirely on your Mac: Whisper on the Apple Silicon GPU via [MLX](https://github.com/ml-explore/mlx), no cloud, no subscription.

[Русская версия →](README.ru.md)

## Features

- **One key, two modes** — *hold* right ⌘ to push-to-talk, *tap* it to toggle a longer recording. Regular right-⌘ shortcuts (⌘C, ⌘V…) keep working.
- **Notch glow** — an Apple-Intelligence-style light animation around the MacBook notch shows state: warm colors while recording, cool while transcribing, a green flash when the text lands. On external displays a virtual notch appears top-center.
- **Fast** — whisper-large-v3-turbo on the GPU transcribes a phrase in ~2 s on an M-series Mac.
- **Custom glossary** — domain terms you dictate ("spid dot center" → `spid.center`) are fixed two ways: the term list biases Whisper's decoder, and regex rules clean up what still slips through.
- **Self-learning** — optionally, an LLM reviews your recent dictations and teaches the glossary new terms automatically. Works with a fully local LLM (Ollama) or CLI agents (Claude Code, Codex, Pi), or hand the task to any coding agent manually.
- **Setup wizard** — pick your speech model and learning backend in a native settings window; everything is also editable from the terminal.
- **Private by design** — audio, transcripts, and the glossary never leave your Mac (unless you explicitly choose a cloud-backed CLI for glossary learning).

## Requirements

- Apple Silicon Mac (M1 or newer), macOS 14+
- Xcode Command Line Tools (`xcode-select --install`)
- Python 3.10+

## Install

One line:

```bash
curl -fsSL https://raw.githubusercontent.com/dojdikkkkkk/WhisperKey/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/dojdikkkkkk/WhisperKey ~/WhisperKey
cd ~/WhisperKey
server/setup.sh   # Python venv + mlx-whisper
./build.sh        # builds and installs /Applications/WhisperKey.app
open /Applications/WhisperKey.app
```

On first launch the setup wizard opens; the speech model (~1.6 GB) downloads on first use.

### Permissions (important!)

WhisperKey needs two grants in **System Settings → Privacy & Security**:

- **Microphone** — to record you;
- **Accessibility** — to deliver text into other apps.

Gotchas we learned the hard way:

- After granting Accessibility, **relaunch the app** — the grant doesn't apply to a running process.
- The right-⌘ hotkey works even *without* Accessibility (modifier-key monitoring is exempt), so "recording works but no text appears" almost always means the Accessibility grant is missing or stale.
- If you build without a code-signing identity (ad-hoc), macOS revokes the grant **on every rebuild**. `build.sh` picks up any Apple Development certificate automatically — creating a free one in Xcode saves you a lot of pain.

## Configuration

Everything lives in `~/.whisperkey/config.json` and in **Settings…** (menu bar icon):

| Key | Default | Meaning |
|---|---|---|
| `model` | `mlx-community/whisper-large-v3-turbo` | MLX Whisper model (HF repo) |
| `learnBackend` | `off` | `ollama` \| `claude` \| `codex` \| `pi` \| `agent-manual` \| `off` |
| `ollamaModel` | `qwen3:4b` | model for the Ollama backend |
| `holdThreshold` | `0.35` | seconds separating a tap from a hold |
| `learnEvery` | `20` | run glossary learning every N dictations |
| `logTranscripts` | `true` | keep a local transcription log (needed for learning) |

Change the model from the terminal:

```bash
# pick any repo from https://huggingface.co/mlx-community?search_models=whisper
python3 -c "import json,pathlib; p=pathlib.Path.home()/'.whisperkey/config.json'; \
c=json.loads(p.read_text()); c['model']='mlx-community/whisper-small-mlx'; \
p.write_text(json.dumps(c,indent=2))"
curl -X POST localhost:8737/restart   # server reloads with the new model
```

## Glossary & self-learning

`server/glossary.json` has two halves:

- `terms` — fed to Whisper as a decoding hint (first ~150 words win, keep it curated);
- `rules` — case-insensitive regex replacements applied to the output.

The file hot-reloads — edit it any time. To seed it from texts you already write, see `server/seed_glossary.py --help`.

With a `learnBackend` configured, every 20 dictations (and on **Learn from recent dictation** in the menu) an LLM compares recent transcriptions against the glossary and appends new terms/rules. The `pi` backend runs `pi -p --no-session --no-tools` with your configured Pi provider and model; authenticate Pi before selecting it. The `agent-manual` backend writes the task to `server/learn_request.md` instead — hand that file to whatever coding agent you use (see [AGENTS.md](AGENTS.md)).

## Architecture

```
right ⌘ ──▶ WhisperKey.app (Swift, menu bar)
              ├─ AVAudioRecorder → 16 kHz WAV
              ├─ POST /transcribe ──▶ transcribe_server.py (Python, localhost:8737)
              │                        └─ mlx-whisper on the GPU + glossary
              └─ text → focused app (AX API → unicode typing → clipboard fallback)
```

The app launches and supervises the server; the model stays loaded between dictations.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Recording works, no text appears | Accessibility grant missing/stale — re-grant, relaunch the app |
| Nothing happens on right ⌘ | Another app intercepts it, or the app isn't running (check menu bar) |
| First dictation very slow | The model is downloading/warming — watch `server/server.log` |
| Empty text from a long recording | Mic recorded silence — check the input device, enable `debugLog` and look for `SILENT RECORDING` |
| Every rebuild asks for permissions again | Ad-hoc signing — create a free Apple Development certificate |

## Roadmap

- **Windows version** — tray app + CUDA/CPU Whisper backend ([windows/README.md](windows/README.md))
- Streaming (real-time) transcription
- Per-app glossaries

## License

[MIT](LICENSE)
