# -*- mode: python ; coding: utf-8 -*-
from pathlib import Path

windows_dir = Path(SPECPATH)
root = windows_dir.parent

a = Analysis(
    [str(windows_dir / "app" / "whisperkey_launcher.py")],
    pathex=[str(windows_dir / "app")],
    binaries=[],
    datas=[
        (str(root / "server" / "cloud_stt.py"), "server"),
        (str(root / "server" / "learn.py"), "server"),
        (str(root / "server" / "glossary.example.json"), "server"),
    ],
    hiddenimports=[
        "faster_whisper",
        "ctranslate2",
        "sounddevice",
        "pystray._win32",
        "PIL._tkinter_finder",
    ],
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="WhisperKey",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    name="WhisperKey",
)
