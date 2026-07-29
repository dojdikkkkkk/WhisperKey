from __future__ import annotations

import logging
import os
import queue
import runpy
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import messagebox

import pystray
from PIL import Image, ImageDraw

from .audio import AudioRecorder
from .backend import SOURCE_SERVER_DIR, run_server
from .client import TranscriptionClient
from .config import APP_DIR, Config
from .hotkey import HotkeyStateMachine, KeyboardHook
from .overlay import Overlay
from .settings import SettingsWindow, open_history
from .text_insert import foreground_window, insert_text


def icon_image(color="#ffffff"):
    image = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((15, 5, 49, 43), radius=17, outline=color, width=6)
    draw.arc((10, 20, 54, 58), 0, 180, fill=color, width=6)
    draw.line((32, 50, 32, 60), fill=color, width=6)
    return image


class App:
    def __init__(self):
        APP_DIR.mkdir(parents=True, exist_ok=True)
        logging.basicConfig(
            filename=APP_DIR / "windows.log",
            level=logging.INFO,
            format="%(asctime)s %(levelname)s %(message)s",
        )
        self.root = tk.Tk()
        self.root.withdraw()
        self.config = Config.load()
        self.overlay = Overlay(self.root)
        self.client = TranscriptionClient()
        self.target_window = 0
        self.work_queue: queue.Queue = queue.Queue()
        self.recorder = AudioRecorder(lambda level: self.enqueue(self.overlay.set_level, level))
        self.settings = SettingsWindow(self.root, self.restart_backend)
        self.machine = HotkeyStateMachine(
            lambda: Config.load().holdThreshold,
            lambda: self.enqueue(self.start_recording),
            lambda: self.enqueue(self.stop_recording),
            lambda: self.enqueue(self.cancel_recording),
        )
        self.hook = KeyboardHook(self.machine, lambda: Config.load().hotkey)
        self.tray = pystray.Icon(
            "WhisperKey",
            icon_image(),
            "WhisperKey",
            menu=pystray.Menu(
                pystray.MenuItem("Settings…", lambda: self.enqueue(self.settings.show)),
                pystray.MenuItem("Dictation history…", lambda: self.enqueue(open_history)),
                pystray.MenuItem("Learn from recent dictation", lambda: self.client.learn()),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem("Quit WhisperKey", lambda: self.enqueue(self.quit)),
            ),
        )

    def run(self) -> int:
        if self.config.setupComplete:
            self.client.ensure_server()
        self.hook.start()
        threading.Thread(target=self.tray.run, name="tray", daemon=True).start()
        self.root.after(20, self._poll_queue)
        if not self.config.setupComplete:
            self.root.after(200, self.settings.show, True)
        self.root.mainloop()
        return 0

    def enqueue(self, callback, *args) -> None:
        self.work_queue.put((callback, args))

    def _poll_queue(self) -> None:
        while True:
            try:
                callback, args = self.work_queue.get_nowait()
            except queue.Empty:
                break
            callback(*args)
        self.root.after(20, self._poll_queue)

    def start_recording(self) -> None:
        try:
            self.target_window = foreground_window()
            self.recorder.start()
            self.overlay.set_mode("recording")
            self.tray.icon = icon_image("#ff5b45")
        except Exception as error:
            logging.exception("Recording failed")
            messagebox.showerror("WhisperKey", f"Could not start microphone:\n{error}")
            self.overlay.set_mode("idle")

    def cancel_recording(self) -> None:
        path = self.recorder.stop()
        if path:
            path.unlink(missing_ok=True)
        self.overlay.set_mode("idle")
        self.tray.icon = icon_image()

    def stop_recording(self) -> None:
        path = self.recorder.stop()
        if not path:
            self.overlay.set_mode("idle")
            return
        self.overlay.set_mode("transcribing")
        self.tray.icon = icon_image("#6a7cff")
        threading.Thread(target=self._transcribe, args=(path,), daemon=True).start()

    def _transcribe(self, path: Path) -> None:
        try:
            status = self.client.wait_until_ready()
            if status.get("status") != "ok":
                raise RuntimeError(status.get("error", "Speech model failed to load"))
            text = self.client.transcribe(path)
            self.enqueue(self._deliver, text)
        except Exception as error:
            logging.exception("Transcription failed")
            path.unlink(missing_ok=True)
            self.enqueue(self._show_error, str(error))

    def _deliver(self, text: str) -> None:
        if text:
            insert_text(text, self.target_window)
            self.overlay.set_mode("inserted")
        else:
            self.overlay.set_mode("idle")
        self.tray.icon = icon_image()

    def _show_error(self, detail: str) -> None:
        self.overlay.set_mode("idle")
        self.tray.icon = icon_image()
        messagebox.showerror("WhisperKey", detail)

    def restart_backend(self) -> None:
        self.client.stop()
        self.config = Config.load()
        self.client = TranscriptionClient()
        self.client.ensure_server()

    def quit(self) -> None:
        self.hook.stop()
        self.client.stop()
        self.tray.stop()
        self.root.destroy()


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if "--server" in argv:
        return run_server()
    if "--learn" in argv:
        runpy.run_path(str(SOURCE_SERVER_DIR / "learn.py"), run_name="__main__")
        return 0
    return App().run()
