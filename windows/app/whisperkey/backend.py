from __future__ import annotations

import array
import io
import json
import logging
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
import wave
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from .config import APP_DIR, Config
from .credentials import load_api_key


SILENCE_PEAK = 0.004
ASSET_DIR = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parents[3]))
SOURCE_SERVER_DIR = ASSET_DIR / "server"
GLOSSARY_PATH = APP_DIR / "glossary.json"
TRANSCRIPTS_PATH = APP_DIR / "transcripts.jsonl"


class Glossary:
    def __init__(self, path: Path):
        self.path = path
        self.mtime = 0.0
        self.prompt = ""
        self.rules: list[tuple[re.Pattern, str]] = []
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            source = SOURCE_SERVER_DIR / "glossary.example.json"
            path.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
        self.reload()

    def reload(self) -> None:
        try:
            mtime = self.path.stat().st_mtime
            if mtime == self.mtime:
                return
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return
        self.mtime = mtime
        words = ", ".join(data.get("terms", [])).split()
        self.prompt = "Glossary: " + " ".join(words[:150]) + "." if words else ""
        rules = []
        for rule in data.get("rules", []):
            try:
                rules.append((re.compile(rule["pattern"], re.IGNORECASE), rule["canonical"]))
            except (KeyError, re.error):
                pass
        self.rules = rules

    def apply(self, text: str) -> str:
        for pattern, canonical in self.rules:
            text = pattern.sub(canonical, text)
        return text


def wav_peak(data: bytes) -> float:
    with wave.open(io.BytesIO(data)) as source:
        if source.getnchannels() != 1 or source.getsampwidth() != 2:
            raise ValueError("expected mono 16-bit WAV audio")
        samples = array.array("h")
        samples.frombytes(source.readframes(source.getnframes()))
    return max((abs(sample) for sample in samples), default=0) / 32768.0


class Backend:
    def __init__(self):
        self.config = Config.load()
        self.glossary = Glossary(GLOSSARY_PATH)
        self.model = None
        self.ready = self.config.transcriptionBackend == "openai"
        self.error = ""
        self.device = ""
    
    def start(self) -> None:
        if self.config.transcriptionBackend == "local":
            threading.Thread(target=self._warm, name="model-loader", daemon=True).start()

    def _warm(self) -> None:
        try:
            logging.info("Loading faster-whisper model=%s", self.config.model)
            import ctranslate2
            from faster_whisper import WhisperModel

            cuda = ctranslate2.get_cuda_device_count() > 0
            self.device = "cuda" if cuda else "cpu"
            compute = "float16" if cuda else "int8"
            self.model = WhisperModel(self.config.model, device=self.device, compute_type=compute)
            self.ready = True
            logging.info("Model ready device=%s compute=%s", self.device, compute)
        except Exception as error:
            self.error = str(error)
            logging.exception("Model startup failed")

    def transcribe(self, data: bytes) -> dict:
        if wav_peak(data) < SILENCE_PEAK:
            return {"text": "", "language": "", "seconds": 0}
        self.glossary.reload()
        started = time.monotonic()
        if self.config.transcriptionBackend == "openai":
            sys.path.insert(0, str(SOURCE_SERVER_DIR))
            from cloud_stt import transcribe

            result = transcribe(
                self.config.cloudEndpoint,
                self.config.cloudModel,
                load_api_key(),
                data,
                self.glossary.prompt,
            )
            raw = result["text"].strip()
            language = result.get("language", "")
        else:
            handle = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
            try:
                handle.write(data)
                handle.close()
                language = None if self.config.language == "auto" else self.config.language
                segments, info = self.model.transcribe(
                    handle.name,
                    language=language,
                    initial_prompt=self.glossary.prompt or None,
                    vad_filter=True,
                    beam_size=5,
                    condition_on_previous_text=False,
                )
                raw = "".join(segment.text for segment in segments).strip()
                language = info.language or ""
            finally:
                try:
                    os.unlink(handle.name)
                except OSError:
                    pass
        corrected = self.glossary.apply(raw)
        self._log(raw, corrected, language)
        return {
            "text": corrected,
            "language": language,
            "seconds": round(time.monotonic() - started, 2),
        }

    def _log(self, raw: str, corrected: str, language: str) -> None:
        if not self.config.logTranscripts:
            return
        APP_DIR.mkdir(parents=True, exist_ok=True)
        entry = {
            "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "raw": raw,
            "text": corrected,
            "language": language,
        }
        with TRANSCRIPTS_PATH.open("a", encoding="utf-8") as output:
            output.write(json.dumps(entry, ensure_ascii=False) + "\n")


def run_server() -> int:
    APP_DIR.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        filename=APP_DIR / "server-windows.log",
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    backend = Backend()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/health":
                return self.respond(404, {"error": "not found"})
            status = "error" if backend.error else ("ok" if backend.ready else "loading")
            self.respond(
                200,
                {
                    "status": status,
                    "backend": backend.config.transcriptionBackend,
                    "model": backend.config.model,
                    "device": backend.device,
                    **({"error": backend.error} if backend.error else {}),
                },
            )

        def do_POST(self):
            if self.path == "/learn":
                script = SOURCE_SERVER_DIR / "learn.py"
                if script.exists():
                    command = (
                        [sys.executable, "--learn"]
                        if getattr(sys, "frozen", False)
                        else [sys.executable, str(script)]
                    )
                    subprocess.Popen(command)
                    return self.respond(200, {"learning": "started"})
                return self.respond(200, {"learning": "unavailable"})
            if self.path != "/transcribe":
                return self.respond(404, {"error": "not found"})
            length = int(self.headers.get("Content-Length", 0))
            if not length:
                return self.respond(400, {"error": "empty body"})
            if backend.error:
                return self.respond(503, {"error": backend.error})
            if not backend.ready:
                return self.respond(503, {"error": "model is still loading"})
            try:
                self.respond(200, backend.transcribe(self.rfile.read(length)))
            except Exception as error:
                self.respond(500, {"error": str(error)})

        def respond(self, status: int, payload: dict):
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", Config.load().port), Handler)
    logging.info("Server listening on 127.0.0.1:%s", Config.load().port)
    backend.start()
    server.serve_forever()
    return 0
