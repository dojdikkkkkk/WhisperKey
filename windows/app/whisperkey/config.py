from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass, fields
from pathlib import Path


APP_DIR = Path.home() / ".whisperkey"
CONFIG_PATH = APP_DIR / "config.json"


@dataclass
class Config:
    port: int = 8737
    model: str = "small"
    transcriptionBackend: str = "local"
    cloudProvider: str = "groq"
    cloudEndpoint: str = "https://api.groq.com/openai/v1/audio/transcriptions"
    cloudModel: str = "whisper-large-v3-turbo"
    setupComplete: bool = False
    holdThreshold: float = 0.35
    hotkey: str = "rightCtrl"
    language: str = "auto"
    learnBackend: str = "off"
    learnEvery: int = 20
    ollamaModel: str = "qwen3:4b"
    logTranscripts: bool = True
    debugLog: bool = False
    launchAtLogin: bool = True

    @classmethod
    def load(cls, path: Path = CONFIG_PATH) -> "Config":
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError, TypeError):
            return cls()
        known = {item.name for item in fields(cls)}
        return cls(**{key: value for key, value in data.items() if key in known})

    def save(self, path: Path = CONFIG_PATH) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        temp = path.with_suffix(".tmp")
        temp.write_text(
            json.dumps(asdict(self), ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        os.replace(temp, path)
