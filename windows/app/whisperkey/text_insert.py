from __future__ import annotations

import ctypes
import time
from ctypes import wintypes


INPUT_KEYBOARD = 1
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_UNICODE = 0x0004
SW_RESTORE = 9

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", wintypes.WORD),
        ("wScan", wintypes.WORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ctypes.c_void_p),
    ]


class INPUT_UNION(ctypes.Union):
    _fields_ = [("ki", KEYBDINPUT)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wintypes.DWORD), ("union", INPUT_UNION)]


def foreground_window() -> int:
    return int(user32.GetForegroundWindow())


def _focus_window(hwnd: int) -> None:
    if not hwnd or not user32.IsWindow(hwnd):
        return
    user32.ShowWindow(hwnd, SW_RESTORE)
    current_thread = kernel32.GetCurrentThreadId()
    target_thread = user32.GetWindowThreadProcessId(hwnd, None)
    attached = bool(
        target_thread
        and target_thread != current_thread
        and user32.AttachThreadInput(current_thread, target_thread, True)
    )
    try:
        user32.SetForegroundWindow(hwnd)
        user32.SetFocus(hwnd)
    finally:
        if attached:
            user32.AttachThreadInput(current_thread, target_thread, False)


def insert_text(text: str, hwnd: int = 0) -> bool:
    if not text:
        return True
    _focus_window(hwnd)
    time.sleep(0.06)
    units = text.encode("utf-16-le")
    code_units = [units[i] | (units[i + 1] << 8) for i in range(0, len(units), 2)]
    inputs = (INPUT * (len(code_units) * 2))()
    for index, unit in enumerate(code_units):
        inputs[index * 2] = INPUT(
            type=INPUT_KEYBOARD,
            union=INPUT_UNION(ki=KEYBDINPUT(wScan=unit, dwFlags=KEYEVENTF_UNICODE)),
        )
        inputs[index * 2 + 1] = INPUT(
            type=INPUT_KEYBOARD,
            union=INPUT_UNION(
                ki=KEYBDINPUT(wScan=unit, dwFlags=KEYEVENTF_UNICODE | KEYEVENTF_KEYUP)
            ),
        )
    sent = user32.SendInput(len(inputs), inputs, ctypes.sizeof(INPUT))
    return sent == len(inputs)
