import io
import json
import tempfile
import unittest
import wave
from pathlib import Path

from whisperkey.backend import Glossary, wav_peak
from whisperkey.config import Config
from whisperkey.hotkey import HotkeyStateMachine, State


class HotkeyTests(unittest.TestCase):
    def setUp(self):
        self.events = []
        self.machine = HotkeyStateMachine(
            lambda: 0.35,
            lambda: self.events.append("start"),
            lambda: self.events.append("stop"),
            lambda: self.events.append("cancel"),
        )

    def test_hold_is_push_to_talk(self):
        self.machine.hotkey_down(1)
        self.machine.hotkey_up(1.5)
        self.assertEqual(self.events, ["start", "stop"])
        self.assertEqual(self.machine.state, State.IDLE)

    def test_tap_toggles_recording(self):
        self.machine.hotkey_down(1)
        self.machine.hotkey_up(1.1)
        self.machine.hotkey_down(2)
        self.machine.hotkey_up(2.1)
        self.assertEqual(self.events, ["start", "stop"])

    def test_shortcut_cancels_accidental_recording(self):
        self.machine.hotkey_down(1)
        self.machine.other_key_down()
        self.machine.hotkey_up(1.1)
        self.assertEqual(self.events, ["start", "cancel"])

    def test_shortcut_does_not_stop_toggle_recording(self):
        self.machine.hotkey_down(1)
        self.machine.hotkey_up(1.1)
        self.machine.hotkey_down(2)
        self.machine.other_key_down()
        self.machine.hotkey_up(2.1)
        self.assertEqual(self.events, ["start"])
        self.assertEqual(self.machine.state, State.TOGGLE_RECORDING)


class DataTests(unittest.TestCase):
    def test_config_tolerates_unknown_and_missing_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.json"
            path.write_text('{"model":"base","futureKey":42}', encoding="utf-8")
            config = Config.load(path)
            self.assertEqual(config.model, "base")
            self.assertEqual(config.port, 8737)

    def test_glossary_applies_rules(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "glossary.json"
            path.write_text(
                json.dumps(
                    {"terms": ["GitHub"], "rules": [{"canonical": "GitHub", "pattern": "git hub"}]}
                ),
                encoding="utf-8",
            )
            self.assertEqual(Glossary(path).apply("open git hub"), "open GitHub")

    def test_wav_peak(self):
        buffer = io.BytesIO()
        with wave.open(buffer, "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(16000)
            output.writeframes((1000).to_bytes(2, "little", signed=True) * 10)
        self.assertAlmostEqual(wav_peak(buffer.getvalue()), 1000 / 32768)


if __name__ == "__main__":
    unittest.main()
