from __future__ import annotations

import array
import tempfile
import threading
import wave
from pathlib import Path

import sounddevice as sd


class AudioRecorder:
    def __init__(self, on_level=None):
        self.on_level = on_level or (lambda _level: None)
        self.stream = None
        self.frames: list[bytes] = []
        self.lock = threading.Lock()

    def start(self) -> None:
        if self.stream:
            return
        self.frames = []
        self.stream = sd.RawInputStream(
            samplerate=16000,
            channels=1,
            dtype="int16",
            blocksize=800,
            callback=self._callback,
        )
        self.stream.start()

    def _callback(self, data, frames, time_info, status) -> None:
        chunk = bytes(data)
        with self.lock:
            self.frames.append(chunk)
        samples = array.array("h")
        samples.frombytes(chunk)
        peak = max((abs(item) for item in samples), default=0) / 32768.0
        self.on_level(min(1.0, peak * 5.0))

    def stop(self) -> Path | None:
        stream, self.stream = self.stream, None
        if not stream:
            return None
        stream.stop()
        stream.close()
        with self.lock:
            payload = b"".join(self.frames)
            self.frames = []
        if not payload:
            return None
        handle = tempfile.NamedTemporaryFile(prefix="whisperkey-", suffix=".wav", delete=False)
        handle.close()
        path = Path(handle.name)
        with wave.open(str(path), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(16000)
            output.writeframes(payload)
        return path
