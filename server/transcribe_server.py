#!/usr/bin/env python3
"""WhisperKey transcription server.

Loads an MLX Whisper model once and serves POST /transcribe (WAV body -> text).
A glossary (glossary.json) biases decoding via initial_prompt and fixes mangled
domain terms with regex rules. Transcriptions are logged to transcripts.jsonl
(configurable) as raw material for the self-learning cycle (learn.py).

Configuration lives in ~/.whisperkey/config.json and is shared with the app.
Bound to localhost only.
"""

import io
import json
import os
import re
import subprocess
import sys
import threading
import time
import wave
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import mlx_whisper
import numpy as np

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.expanduser("~/.whisperkey/config.json")
GLOSSARY_PATH = os.path.join(BASE_DIR, "glossary.json")
TRANSCRIPTS_PATH = os.path.join(BASE_DIR, "transcripts.jsonl")
SILENCE_PEAK = 0.004  # normalized amplitude below which we skip transcription

DEFAULTS = {
    "port": 8737,
    "model": "mlx-community/whisper-large-v3-turbo",
    "learnBackend": "off",
    "learnEvery": 20,
    "logTranscripts": True,
}


def load_config():
    cfg = dict(DEFAULTS)
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            cfg.update(json.load(f))
    except (OSError, json.JSONDecodeError):
        pass
    return cfg


config = load_config()
HOST = "127.0.0.1"
PORT = int(config["port"])
MODEL_NAME = config["model"]

model_ready = False
print(f"Warming up {MODEL_NAME}...", flush=True)
t0 = time.time()


def warm_up():
    global model_ready
    mlx_whisper.transcribe(np.zeros(16000, dtype=np.float32), path_or_hf_repo=MODEL_NAME)
    model_ready = True
    print(f"Model warm in {time.time() - t0:.1f}s", flush=True)


def wav_to_float32(data):
    """Decode 16 kHz mono 16-bit WAV bytes into a normalized float32 array."""
    with wave.open(io.BytesIO(data)) as w:
        frames = w.readframes(w.getnframes())
    return np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0


class Glossary:
    """glossary.json wrapper with mtime-based hot reload."""

    def __init__(self, path):
        self.path = path
        self.mtime = 0.0
        self.prompt = ""
        self.rules = []
        self.reload_if_changed()

    def reload_if_changed(self):
        try:
            mtime = os.path.getmtime(self.path)
        except OSError:
            return
        if mtime == self.mtime:
            return
        try:
            with open(self.path, encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError) as e:
            print(f"Glossary reload failed: {e}", flush=True)
            return
        self.mtime = mtime
        # Whisper degrades with long prompts — cap at ~150 words, first terms win
        terms = data.get("terms", [])
        words = ", ".join(terms).split()
        self.prompt = "Glossary: " + " ".join(words[:150]) + "." if terms else ""
        self.rules = []
        for rule in data.get("rules", []):
            try:
                self.rules.append((re.compile(rule["pattern"], re.IGNORECASE), rule["canonical"]))
            except re.error as e:
                print(f"Bad pattern for {rule.get('canonical')}: {e}", flush=True)
        print(f"Glossary loaded: {len(terms)} terms, {len(self.rules)} rules", flush=True)

    def apply_rules(self, text):
        for pattern, canonical in self.rules:
            text = pattern.sub(canonical, text)
        return text


glossary = Glossary(GLOSSARY_PATH)
transcription_count = 0
learn_lock = threading.Lock()
server = None


def log_transcription(raw, corrected, language):
    if not config.get("logTranscripts", True):
        return
    entry = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "raw": raw,
        "text": corrected,
        "language": language,
    }
    with open(TRANSCRIPTS_PATH, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def run_learn_async():
    """Run learn.py in a background subprocess; skip if one is already running."""
    if config.get("learnBackend", "off") == "off":
        return False
    if not learn_lock.acquire(blocking=False):
        return False

    def worker():
        try:
            print("Learning: running learn.py...", flush=True)
            result = subprocess.run(
                [sys.executable, os.path.join(BASE_DIR, "learn.py")],
                capture_output=True, text=True, timeout=300,
            )
            print(f"Learning finished (rc={result.returncode}): "
                  f"{(result.stdout or result.stderr).strip()[-300:]}", flush=True)
        except Exception as e:
            print(f"Learning failed: {e}", flush=True)
        finally:
            learn_lock.release()

    threading.Thread(target=worker, daemon=True).start()
    return True


def restart_soon():
    """Re-exec the server so config changes (e.g. a new model) take effect."""
    def worker():
        time.sleep(0.5)
        print("Restarting to apply new config...", flush=True)
        if server:
            server.server_close()
        os.execv(sys.executable, [sys.executable] + sys.argv)

    threading.Thread(target=worker, daemon=True).start()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self._respond(200, {
                "status": "ok" if model_ready else "loading",
                "model": MODEL_NAME,
            })
        else:
            self._respond(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/learn":
            started = run_learn_async()
            self._respond(200, {"learning": "started" if started else "unavailable"})
            return
        if self.path == "/restart":
            self._respond(200, {"restarting": True})
            restart_soon()
            return
        if self.path != "/transcribe":
            self._respond(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", 0))
        if length == 0:
            self._respond(400, {"error": "empty body"})
            return
        if not model_ready:
            self._respond(503, {"error": "model is still loading"})
            return
        body = self.rfile.read(length)
        glossary.reload_if_changed()
        t0 = time.time()
        try:
            audio = wav_to_float32(body)
            # mlx-whisper has no VAD — gate out silent recordings ourselves,
            # otherwise the model hallucinates on empty audio
            if audio.size == 0 or np.abs(audio).max() < SILENCE_PEAK:
                print("Skipped silent recording", flush=True)
                self._respond(200, {"text": "", "language": "", "seconds": 0})
                return
            result = mlx_whisper.transcribe(
                audio,
                path_or_hf_repo=MODEL_NAME,
                condition_on_previous_text=False,  # faster, prevents repetition loops
                initial_prompt=glossary.prompt or None,
            )
            raw = result["text"].strip()
            language = result.get("language", "")
        except Exception as e:
            self._respond(500, {"error": str(e)})
            return
        text = glossary.apply_rules(raw)
        elapsed = time.time() - t0
        print(f"Transcribed {elapsed:.1f}s lang={language}: {text[:80]}", flush=True)
        log_transcription(raw, text, language)

        global transcription_count
        transcription_count += 1
        if transcription_count % int(config["learnEvery"]) == 0:
            run_learn_async()

        self._respond(200, {"text": text, "language": language, "seconds": round(elapsed, 2)})

    def _respond(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass  # request lines already logged above; keep stdout clean


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    threading.Thread(target=warm_up, daemon=True).start()
    print(f"Listening on {HOST}:{PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)
