from __future__ import annotations

import ctypes
import threading
import time
from ctypes import wintypes
from enum import Enum, auto
from typing import Callable


WH_KEYBOARD_LL = 13
WM_KEYDOWN = 0x0100
WM_KEYUP = 0x0101
WM_SYSKEYDOWN = 0x0104
WM_SYSKEYUP = 0x0105
LLKHF_INJECTED = 0x10
VK_RWIN = 0x5C
VK_RCONTROL = 0xA3


class KBDLLHOOKSTRUCT(ctypes.Structure):
    _fields_ = [
        ("vkCode", wintypes.DWORD),
        ("scanCode", wintypes.DWORD),
        ("flags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ctypes.c_void_p),
    ]


HOOKPROC = ctypes.WINFUNCTYPE(
    ctypes.c_ssize_t, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM
)
user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
user32.SetWindowsHookExW.argtypes = [ctypes.c_int, HOOKPROC, wintypes.HINSTANCE, wintypes.DWORD]
user32.SetWindowsHookExW.restype = wintypes.HHOOK
user32.CallNextHookEx.restype = ctypes.c_ssize_t


class State(Enum):
    IDLE = auto()
    PRESSED = auto()
    TOGGLE_RECORDING = auto()


class HotkeyStateMachine:
    def __init__(
        self,
        hold_threshold: Callable[[], float],
        on_start: Callable[[], None],
        on_stop: Callable[[], None],
        on_cancel: Callable[[], None],
    ):
        self.hold_threshold = hold_threshold
        self.on_start = on_start
        self.on_stop = on_stop
        self.on_cancel = on_cancel
        self.state = State.IDLE
        self.pressed_at = 0.0
        self.was_recording = False
        self.used_as_modifier = False

    def hotkey_down(self, now: float | None = None) -> None:
        if self.state == State.PRESSED:
            return
        self.was_recording = self.state == State.TOGGLE_RECORDING
        self.state = State.PRESSED
        self.pressed_at = time.monotonic() if now is None else now
        self.used_as_modifier = False
        if not self.was_recording:
            self.on_start()

    def other_key_down(self) -> None:
        if self.state == State.PRESSED:
            self.used_as_modifier = True

    def hotkey_up(self, now: float | None = None) -> None:
        if self.state != State.PRESSED:
            return
        elapsed = (time.monotonic() if now is None else now) - self.pressed_at
        if self.used_as_modifier:
            if self.was_recording:
                self.state = State.TOGGLE_RECORDING
            else:
                self.state = State.IDLE
                self.on_cancel()
        elif self.was_recording or elapsed >= self.hold_threshold():
            self.state = State.IDLE
            self.on_stop()
        else:
            self.state = State.TOGGLE_RECORDING


class KeyboardHook:
    def __init__(self, machine: HotkeyStateMachine, key_name: Callable[[], str]):
        self.machine = machine
        self.key_name = key_name
        self.thread: threading.Thread | None = None
        self.thread_id = 0
        self.hook = None
        self.callback = HOOKPROC(self._callback)

    @property
    def virtual_key(self) -> int:
        return VK_RWIN if self.key_name() == "rightWin" else VK_RCONTROL

    def start(self) -> None:
        if self.thread and self.thread.is_alive():
            return
        self.thread = threading.Thread(target=self._run, name="keyboard-hook", daemon=True)
        self.thread.start()

    def stop(self) -> None:
        if self.thread_id:
            user32.PostThreadMessageW(self.thread_id, 0x0012, 0, 0)

    def _run(self) -> None:
        self.thread_id = kernel32.GetCurrentThreadId()
        self.hook = user32.SetWindowsHookExW(WH_KEYBOARD_LL, self.callback, None, 0)
        if not self.hook:
            raise ctypes.WinError(ctypes.get_last_error())
        message = wintypes.MSG()
        while user32.GetMessageW(ctypes.byref(message), None, 0, 0) > 0:
            user32.TranslateMessage(ctypes.byref(message))
            user32.DispatchMessageW(ctypes.byref(message))
        user32.UnhookWindowsHookEx(self.hook)

    def _callback(self, code: int, wparam: int, lparam: int) -> int:
        if code >= 0:
            event = ctypes.cast(lparam, ctypes.POINTER(KBDLLHOOKSTRUCT)).contents
            if not event.flags & LLKHF_INJECTED:
                down = wparam in (WM_KEYDOWN, WM_SYSKEYDOWN)
                up = wparam in (WM_KEYUP, WM_SYSKEYUP)
                if event.vkCode == self.virtual_key:
                    if down:
                        self.machine.hotkey_down()
                    elif up:
                        self.machine.hotkey_up()
                elif down:
                    self.machine.other_key_down()
        return user32.CallNextHookEx(self.hook, code, wparam, lparam)
