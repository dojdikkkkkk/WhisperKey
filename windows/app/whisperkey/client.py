from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from .config import Config


class TranscriptionClient:
    def __init__(self):
        self.process: subprocess.Popen | None = None

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{Config.load().port}"

    def ensure_server(self) -> None:
        if self.health().get("status") in {"ok", "loading"}:
            return
        if getattr(sys, "frozen", False):
            command = [sys.executable, "--server"]
        else:
            command = [sys.executable, "-m", "whisperkey", "--server"]
        flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        self.process = subprocess.Popen(command, creationflags=flags)

    def health(self) -> dict:
        try:
            with urlopen(self.base_url + "/health", timeout=1) as response:
                return json.load(response)
        except (OSError, ValueError):
            return {}

    def wait_until_ready(self, timeout: float = 180) -> dict:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            status = self.health()
            if status.get("status") in {"ok", "error"}:
                return status
            time.sleep(0.4)
        return {"status": "error", "error": "Model startup timed out"}

    def transcribe(self, wav_path: Path) -> str:
        data = wav_path.read_bytes()
        wav_path.unlink(missing_ok=True)
        request = Request(
            self.base_url + "/transcribe",
            data=data,
            method="POST",
            headers={"Content-Type": "audio/wav"},
        )
        try:
            with urlopen(request, timeout=180) as response:
                payload = json.load(response)
        except HTTPError as error:
            try:
                detail = json.load(error).get("error", "")
            except Exception:
                detail = ""
            raise RuntimeError(detail or f"Transcription failed (HTTP {error.code})") from None
        except URLError as error:
            raise RuntimeError(f"Transcription server is unavailable: {error.reason}") from None
        return str(payload.get("text", ""))

    def learn(self) -> None:
        try:
            urlopen(Request(self.base_url + "/learn", data=b"", method="POST"), timeout=2).close()
        except OSError:
            pass

    def stop(self) -> None:
        if self.process and self.process.poll() is None:
            self.process.terminate()
