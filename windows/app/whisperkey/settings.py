from __future__ import annotations

import os
import sys
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk
import winreg

from .config import APP_DIR, Config
from .credentials import load_api_key, save_api_key


RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"


def set_launch_at_login(enabled: bool) -> None:
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as key:
        if enabled:
            executable = Path(sys.executable).resolve()
            command = f'"{executable}"' if getattr(sys, "frozen", False) else ""
            if command:
                winreg.SetValueEx(key, "WhisperKey", 0, winreg.REG_SZ, command)
        else:
            try:
                winreg.DeleteValue(key, "WhisperKey")
            except FileNotFoundError:
                pass


class SettingsWindow:
    def __init__(self, root: tk.Tk, on_saved):
        self.root = root
        self.on_saved = on_saved
        self.window: tk.Toplevel | None = None

    def show(self, first_run: bool = False) -> None:
        if self.window and self.window.winfo_exists():
            self.window.deiconify()
            self.window.lift()
            return
        config = Config.load()
        window = self.window = tk.Toplevel(self.root)
        window.title("WhisperKey — Settings")
        window.geometry("570x520")
        window.resizable(False, False)
        frame = ttk.Frame(window, padding=20)
        frame.pack(fill="both", expand=True)

        backend = tk.StringVar(value=config.transcriptionBackend)
        model = tk.StringVar(value=config.model)
        language = tk.StringVar(value=config.language)
        hotkey = tk.StringVar(value=config.hotkey)
        endpoint = tk.StringVar(value=config.cloudEndpoint)
        cloud_model = tk.StringVar(value=config.cloudModel)
        api_key = tk.StringVar(value=load_api_key())
        launch = tk.BooleanVar(value=config.launchAtLogin)
        debug = tk.BooleanVar(value=config.debugLog)

        ttk.Label(frame, text="WhisperKey for Windows", font=("Segoe UI", 18, "bold")).grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, 14)
        )
        ttk.Label(frame, text="Speech backend").grid(row=1, column=0, sticky="w", pady=5)
        ttk.Combobox(
            frame, textvariable=backend, values=("local", "openai"), state="readonly", width=36
        ).grid(row=1, column=1, sticky="ew")
        ttk.Label(frame, text="Local model").grid(row=2, column=0, sticky="w", pady=5)
        ttk.Combobox(
            frame,
            textvariable=model,
            values=("tiny", "base", "small", "medium", "large-v3", "turbo"),
            width=36,
        ).grid(row=2, column=1, sticky="ew")
        ttk.Label(frame, text="Language").grid(row=3, column=0, sticky="w", pady=5)
        ttk.Combobox(
            frame, textvariable=language, values=("auto", "ru", "en"), width=36
        ).grid(row=3, column=1, sticky="ew")
        ttk.Label(frame, text="Dictation key").grid(row=4, column=0, sticky="w", pady=5)
        ttk.Combobox(
            frame,
            textvariable=hotkey,
            values=("rightCtrl", "rightWin"),
            state="readonly",
            width=36,
        ).grid(row=4, column=1, sticky="ew")
        ttk.Separator(frame).grid(row=5, column=0, columnspan=2, sticky="ew", pady=14)
        ttk.Label(frame, text="Cloud endpoint").grid(row=6, column=0, sticky="w", pady=5)
        ttk.Entry(frame, textvariable=endpoint, width=40).grid(row=6, column=1, sticky="ew")
        ttk.Label(frame, text="Cloud model").grid(row=7, column=0, sticky="w", pady=5)
        ttk.Entry(frame, textvariable=cloud_model, width=40).grid(row=7, column=1, sticky="ew")
        ttk.Label(frame, text="API key").grid(row=8, column=0, sticky="w", pady=5)
        ttk.Entry(frame, textvariable=api_key, show="•", width=40).grid(
            row=8, column=1, sticky="ew"
        )
        ttk.Checkbutton(frame, text="Launch at Windows login", variable=launch).grid(
            row=9, column=0, columnspan=2, sticky="w", pady=(14, 4)
        )
        ttk.Checkbutton(frame, text="Enable debug logging", variable=debug).grid(
            row=10, column=0, columnspan=2, sticky="w"
        )
        ttk.Label(
            frame,
            text=(
                "Quick tap: start/stop toggle recording. Hold: push-to-talk.\n"
                "The first local dictation downloads the selected model."
            ),
            foreground="#555555",
        ).grid(row=11, column=0, columnspan=2, sticky="w", pady=16)

        def save():
            config.transcriptionBackend = backend.get()
            config.model = model.get().strip() or "small"
            config.language = language.get().strip() or "auto"
            config.hotkey = hotkey.get()
            config.cloudEndpoint = endpoint.get().strip()
            config.cloudModel = cloud_model.get().strip()
            config.launchAtLogin = launch.get()
            config.debugLog = debug.get()
            config.setupComplete = True
            try:
                config.save()
                if api_key.get().strip():
                    save_api_key(api_key.get().strip())
                set_launch_at_login(config.launchAtLogin)
                self.on_saved()
                window.destroy()
            except Exception as error:
                messagebox.showerror("WhisperKey", str(error), parent=window)

        ttk.Button(frame, text="Save and restart backend", command=save).grid(
            row=12, column=1, sticky="e"
        )
        frame.columnconfigure(1, weight=1)
        if first_run:
            window.protocol("WM_DELETE_WINDOW", save)


def open_history() -> None:
    APP_DIR.mkdir(parents=True, exist_ok=True)
    path = APP_DIR / "transcripts.jsonl"
    path.touch(exist_ok=True)
    os.startfile(path)
