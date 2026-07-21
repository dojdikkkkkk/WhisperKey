# WhisperKey

**Local-first dictation for macOS, triggered by the right ⌘ key.** Speak in any app — the text appears at your cursor ~2 seconds later. Run Whisper entirely on your Apple Silicon GPU via [MLX](https://github.com/ml-explore/mlx), or use your own OpenAI-compatible speech-to-text API key.

[Русская версия →](README.ru.md)

## Features

- **One key, two modes** — *hold* right ⌘ to push-to-talk, *tap* it to toggle a longer recording. Regular right-⌘ shortcuts (⌘C, ⌘V…) keep working.
- **Notch glow** — an Apple-Intelligence-style light animation around the MacBook notch shows state: warm colors while recording, cool while transcribing, a green flash when the text lands. On external displays a virtual notch appears top-center.
- **Local or cloud STT** — run whisper-large-v3-turbo on the GPU, use the built-in Groq preset, or configure another OpenAI-compatible transcription endpoint.
- **Custom glossary** — domain terms you dictate ("spid dot center" → `spid.center`) are fixed two ways: the term list biases Whisper's decoder, and regex rules clean up what still slips through.
- **Self-learning** — optionally, an LLM reviews your recent dictations and teaches the glossary new terms automatically. Works with a fully local LLM (Ollama) or CLI agents (Claude Code, Codex), or hand the task to any coding agent manually.
- **Setup wizard** — choose Local MLX or Cloud API, then pick your speech model and learning backend in a native settings window.
- **Private by design** — Local MLX keeps audio on your Mac. Cloud mode stores the API key in macOS Keychain and sends audio only to the endpoint you configure.

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

On first launch the setup wizard opens. Choose **Local MLX** to download a speech model on first use, or **Cloud API** to avoid downloading model weights.

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
| `model` | `mlx-community/whisper-large-v3-turbo` | Local MLX Whisper model (HF repo) |
| `transcriptionBackend` | `local` | `local` \| `openai` |
| `cloudProvider` | `groq` | `groq` \| `custom` |
| `cloudEndpoint` | Groq transcription URL | Full OpenAI-compatible `/audio/transcriptions` endpoint |
| `cloudModel` | `whisper-large-v3-turbo` | provider-specific transcription model |
| `learnBackend` | `off` | `ollama` \| `claude` \| `codex` \| `agent-manual` \| `off` |
| `ollamaModel` | `qwen3:4b` | model for the Ollama backend |
| `holdThreshold` | `0.35` | seconds separating a tap from a hold |
| `learnEvery` | `20` | run glossary learning every N dictations |
| `logTranscripts` | `true` | keep a local transcription log (needed for learning) |

The cloud API key is stored in macOS Keychain and is never written to this file.

Change the local model from the terminal:

```bash
# pick any repo from https://huggingface.co/mlx-community?search_models=whisper
python3 -c "import json,pathlib; p=pathlib.Path.home()/'.whisperkey/config.json'; \
c=json.loads(p.read_text()); c['model']='mlx-community/whisper-small-mlx'; \
p.write_text(json.dumps(c,indent=2))"
curl -X POST localhost:8737/restart   # server reloads with the new model
```

### Cloud speech-to-text

In **Settings… → Speech-to-text**, choose **Cloud API**:

- **Groq** pre-fills `https://api.groq.com/openai/v1/audio/transcriptions` and `whisper-large-v3-turbo`. Groq's direct API uses that model name without a `groq/` prefix.
- **Custom** accepts a full OpenAI-compatible transcription endpoint and provider-specific model name, including gateway-style names when the gateway requires them.

Enter the API key and click **Save & Use Cloud STT**. WhisperKey sends the WAV as standard multipart fields (`file`, `model`, and the glossary `prompt`) with Bearer authentication. Remote endpoints must use HTTPS; HTTP is allowed only for loopback development endpoints. Cloud failures produce a macOS notification and never trigger an automatic local-model fallback.

Cloud mode sends recorded audio and glossary prompt terms to the configured provider. Local transcript logging remains controlled by `logTranscripts`.

## Glossary & self-learning

`server/glossary.json` has two halves:

- `terms` — sent as a decoding prompt to the active transcription backend (first ~150 words win, keep it curated);
- `rules` — case-insensitive regex replacements applied to the output.

The file hot-reloads — edit it any time. To seed it from texts you already write, see `server/seed_glossary.py --help`.

With a `learnBackend` configured, every 20 dictations (and on **Learn from recent dictation** in the menu) an LLM compares recent transcriptions against the glossary and appends new terms/rules. The `agent-manual` backend writes the task to `server/learn_request.md` instead — hand that file to whatever coding agent you use (see [AGENTS.md](AGENTS.md)).

## Architecture

```
right ⌘ ──▶ WhisperKey.app (Swift, menu bar)
              ├─ AVAudioRecorder → 16 kHz WAV
              ├─ POST /transcribe ──▶ transcribe_server.py (Python, localhost:8737)
              │                        ├─ Local: mlx-whisper on the GPU
              │                        ├─ Cloud: OpenAI-compatible STT API
              │                        └─ glossary + history + self-learning
              └─ text → focused app (AX API → unicode typing → clipboard fallback)
```

The app launches and supervises the local gateway. Local mode keeps the model loaded between dictations; cloud mode skips MLX warm-up and does not download model weights.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Recording works, no text appears | Accessibility grant missing/stale — re-grant, relaunch the app |
| Nothing happens on right ⌘ | Another app intercepts it, or the app isn't running (check menu bar) |
| First local dictation very slow | The model is downloading/warming — watch `server/server.log` |
| Cloud transcription fails | Check the macOS notification and `server/server.log`; verify the endpoint, model, Keychain API key, account quota, and provider status |
| Empty text from a long recording | Mic recorded silence — check the input device, enable `debugLog` and look for `SILENT RECORDING` |
| Every rebuild asks for permissions again | Ad-hoc signing — create a free Apple Development certificate |

## Roadmap

- **Windows version** — tray app + CUDA/CPU Whisper backend ([windows/README.md](windows/README.md))
- Streaming (real-time) transcription
- Per-app glossaries

## License

[MIT](LICENSE)
