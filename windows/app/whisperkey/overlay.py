from __future__ import annotations

import ctypes
import math
import time
import tkinter as tk


GWL_EXSTYLE = -20
WS_EX_TOOLWINDOW = 0x00000080
WS_EX_NOACTIVATE = 0x08000000
MONITOR_DEFAULTTOPRIMARY = 1


class Overlay:
    COLORS = {
        "recording": ("#ff3158", "#ff8a24"),
        "transcribing": ("#4f7cff", "#b44cff"),
        "inserted": ("#22d683", "#4ce0c1"),
    }

    def __init__(self, root: tk.Tk):
        self.root = root
        self.mode = "idle"
        self.level = 0.0
        self.window = tk.Toplevel(root)
        self.window.withdraw()
        self.window.overrideredirect(True)
        self.window.attributes("-topmost", True)
        self.window.configure(bg="#010101")
        self.window.wm_attributes("-transparentcolor", "#010101")
        self.canvas = tk.Canvas(
            self.window, width=250, height=72, bg="#010101", highlightthickness=0
        )
        self.canvas.pack()
        self.window.update_idletasks()
        hwnd = self.window.winfo_id()
        user32 = ctypes.windll.user32
        style = user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
        user32.SetWindowLongW(hwnd, GWL_EXSTYLE, style | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE)
        self.started = time.monotonic()
        self._tick()

    def set_mode(self, mode: str) -> None:
        self.root.after(0, self._set_mode, mode)

    def _set_mode(self, mode: str) -> None:
        self.mode = mode
        if mode == "idle":
            self.window.withdraw()
        else:
            width = self.window.winfo_screenwidth()
            self.window.geometry(f"250x72+{max(0, (width - 250) // 2)}+0")
            self.window.deiconify()
            self.window.lift()
        if mode == "inserted":
            self.root.after(550, lambda: self._set_mode("idle") if self.mode == "inserted" else None)

    def set_level(self, level: float) -> None:
        self.level = max(0.0, min(1.0, level))

    def _tick(self) -> None:
        if self.mode != "idle":
            self._draw()
        self.root.after(33, self._tick)

    def _draw(self) -> None:
        self.canvas.delete("all")
        first, second = self.COLORS.get(self.mode, ("#333333", "#666666"))
        self.canvas.create_oval(15, 4, 235, 66, fill=first, outline="")
        self.canvas.create_oval(20, 9, 230, 61, fill=second, outline="")
        self.canvas.create_oval(24, 13, 226, 57, fill="#080808", outline="")
        now = time.monotonic() - self.started
        count = 22
        for index in range(count):
            x = 46 + index * 7.3
            if self.mode == "recording":
                dance = abs(math.sin(now * 6.3 + index * 1.7))
                height = 5 + (5 + 22 * self.level) * dance
            elif self.mode == "transcribing":
                height = 8 + 18 * (0.5 + 0.5 * math.sin(now * 4 - index * 0.55))
            else:
                height = 24
            color = first if index < count / 2 else second
            self.canvas.create_line(x, 35 - height / 2, x, 35 + height / 2, fill=color, width=4)
