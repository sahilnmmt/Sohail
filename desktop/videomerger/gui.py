"""The window: the same editing as the Android app, plus subtitles. Saves and opens recipes."""

from __future__ import annotations

import os
import queue
import subprocess
import sys
import threading
import tkinter as tk
from dataclasses import dataclass
from pathlib import Path
from tkinter import filedialog, messagebox, simpledialog, ttk

from . import __version__, engine, sources
from . import ffmpeg as tools
from .recipe import RESOLUTIONS, WHISPER_MODELS, Clip, Recipe, RecipeError, Sound, Subtitles, is_url, load, parse_time

VIDEO_TYPES = [("Videos", "*.mp4 *.mov *.m4v *.mkv *.webm *.avi *.3gp"), ("All files", "*.*")]
SOUND_TYPES = [("Sound or video", "*.mp3 *.m4a *.wav *.aac *.ogg *.flac *.mp4 *.mov *.mkv *.webm"), ("All files", "*.*")]
STAGES = {"download": "Downloading", "probe": "Reading clips", "speech": "Listening for speech (subtitles)", "encode": "Exporting"}


def fmt(seconds: float | None) -> str:
    if seconds is None:
        return "?"
    tenths = int(round(seconds * 10))
    m, t = divmod(tenths, 600)
    return f"{m}:{t // 10:02d}.{t % 10}"


@dataclass
class Item:
    """A clip in the list, with what was read from its file (None for links not downloaded yet)."""

    clip: Clip
    info: tools.MediaInfo | None

    @property
    def name(self) -> str:
        return self.clip.path if is_url(self.clip.path) else Path(self.clip.path).name

    @property
    def end(self) -> float | None:
        if self.clip.end is not None:
            return self.clip.end
        return self.info.duration if self.info else None

    @property
    def kept(self) -> float | None:
        return None if self.end is None else self.end - self.clip.start


class TrimDialog(simpledialog.Dialog):
    def __init__(self, parent, title: str, length: float | None, start: float, end: float | None):
        self.length, self.start, self.end = length, start, end
        self.result = None
        super().__init__(parent, title)

    def body(self, master):
        ttk.Label(master, text=f"Full length: {fmt(self.length)}   (seconds, or m:ss)").grid(row=0, column=0, columnspan=2, sticky="w", pady=(0, 8))
        ttk.Label(master, text="Start").grid(row=1, column=0, sticky="w")
        ttk.Label(master, text="End").grid(row=2, column=0, sticky="w")
        self.start_var = tk.StringVar(value=fmt(self.start))
        self.end_var = tk.StringVar(value=fmt(self.end) if self.end is not None else "")
        first = ttk.Entry(master, textvariable=self.start_var, width=12)
        first.grid(row=1, column=1, pady=2)
        ttk.Entry(master, textvariable=self.end_var, width=12).grid(row=2, column=1, pady=2)
        ttk.Label(master, text="Leave End empty to keep to the end.").grid(row=3, column=0, columnspan=2, sticky="w", pady=(8, 0))
        return first

    def validate(self):
        try:
            start = parse_time(self.start_var.get(), "Start") or 0.0
            end = parse_time(self.end_var.get(), "End")
        except RecipeError as e:
            messagebox.showerror("Trim", str(e), parent=self)
            return False
        if self.length is not None and end is not None and end >= self.length - 0.05:
            end = None
        if end is not None and end <= start:
            messagebox.showerror("Trim", "End must be after start.", parent=self)
            return False
        if self.length is not None and start >= self.length:
            messagebox.showerror("Trim", "Start is past the end of the video.", parent=self)
            return False
        self.result = (start, end)
        return True


class App:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.items: list[Item] = []
        self.sound: Sound | None = None
        self.sound_info: tools.MediaInfo | None = None
        self.job: engine.Job | None = None
        self.events: queue.Queue = queue.Queue()
        self.last_output: str | None = None

        root.title("Video Merger")
        root.minsize(760, 640)
        self._menu()
        self._build()
        self._refresh()
        root.after(100, self._poll)

    # -- layout -----------------------------------------------------------

    def _menu(self):
        bar = tk.Menu(self.root)
        file = tk.Menu(bar, tearoff=False)
        file.add_command(label="New", command=self.new)
        file.add_command(label="Open recipe…", command=self.open_recipe)
        file.add_command(label="Save recipe…", command=self.save_recipe)
        file.add_separator()
        file.add_command(label="Exit", command=self.root.destroy)
        bar.add_cascade(label="File", menu=file)
        help_menu = tk.Menu(bar, tearoff=False)
        help_menu.add_command(label="About", command=self.about)
        bar.add_cascade(label="Help", menu=help_menu)
        self.root.config(menu=bar)

    def _build(self):
        pad = {"padx": 8, "pady": 4}
        main = ttk.Frame(self.root, padding=8)
        main.pack(fill="both", expand=True)
        main.columnconfigure(0, weight=1)
        main.rowconfigure(0, weight=1)

        # Clips
        clips = ttk.LabelFrame(main, text="Clips (joined in this order)", padding=6)
        clips.grid(row=0, column=0, columnspan=2, sticky="nsew", **pad)
        clips.columnconfigure(0, weight=1)
        clips.rowconfigure(0, weight=1)
        columns = ("n", "name", "length", "trim", "rotate", "size")
        self.tree = ttk.Treeview(clips, columns=columns, show="headings", selectmode="browse", height=6)
        for col, title, width, anchor in [
            ("n", "#", 36, "e"),
            ("name", "File", 260, "w"),
            ("length", "Length", 70, "e"),
            ("trim", "Trim", 120, "center"),
            ("rotate", "Rotate", 60, "center"),
            ("size", "Size", 90, "center"),
        ]:
            self.tree.heading(col, text=title)
            self.tree.column(col, width=width, anchor=anchor, stretch=col == "name")
        self.tree.grid(row=0, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(clips, orient="vertical", command=self.tree.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self.tree.configure(yscrollcommand=scroll.set)
        self.tree.bind("<<TreeviewSelect>>", lambda e: self._refresh_buttons())
        self.tree.bind("<Double-1>", lambda e: self.trim_clip())
        self.tree.bind("<Delete>", lambda e: self.remove_clip())

        buttons = ttk.Frame(clips)
        buttons.grid(row=0, column=2, sticky="ns", padx=(8, 0))
        self.clip_buttons = {}
        for key, label, command in [
            ("add", "Add videos…", self.add_videos),
            ("link", "Add from link…", self.add_link),
            ("up", "Move up", lambda: self.move(-1)),
            ("down", "Move down", lambda: self.move(1)),
            ("trim", "Trim…", self.trim_clip),
            ("rotate", "Rotate 90°", self.rotate_clip),
            ("remove", "Remove", self.remove_clip),
        ]:
            button = ttk.Button(buttons, text=label, command=command, width=16)
            button.pack(fill="x", pady=2)
            self.clip_buttons[key] = button
        self.total_label = ttk.Label(clips)
        self.total_label.grid(row=1, column=0, sticky="w", pady=(6, 0))

        # Settings
        settings = ttk.LabelFrame(main, text="Picture", padding=6)
        settings.grid(row=1, column=0, sticky="nsew", **pad)
        ttk.Label(settings, text="Output size").grid(row=0, column=0, sticky="w")
        self.resolution = tk.StringVar(value="720p")
        ttk.Combobox(settings, textvariable=self.resolution, values=list(RESOLUTIONS), state="readonly", width=10).grid(row=0, column=1, sticky="w", padx=6)
        ttk.Label(settings, text="Frames per second").grid(row=1, column=0, sticky="w")
        self.fps = tk.StringVar(value="30")
        ttk.Combobox(settings, textvariable=self.fps, values=["24", "25", "30", "50", "60"], state="readonly", width=10).grid(row=1, column=1, sticky="w", padx=6, pady=2)
        ttk.Label(settings, text="The first clip decides landscape or portrait;\nother shapes get black bars.", foreground="gray").grid(row=2, column=0, columnspan=2, sticky="w", pady=(4, 0))

        # Sound
        sound = ttk.LabelFrame(main, text="Sound", padding=6)
        sound.grid(row=1, column=1, sticky="nsew", **pad)
        sound.columnconfigure(0, weight=1)
        self.mute = tk.BooleanVar(value=False)
        ttk.Checkbutton(sound, text="Remove the clips' own sound", variable=self.mute, command=self._refresh).grid(row=0, column=0, columnspan=4, sticky="w")
        self.sound_label = ttk.Label(sound, wraplength=330)
        self.sound_label.grid(row=1, column=0, columnspan=4, sticky="w", pady=4)
        self.sound_add = ttk.Button(sound, text="Add sound…", command=self.add_sound)
        self.sound_add.grid(row=2, column=0, sticky="w")
        self.sound_trim = ttk.Button(sound, text="Trim…", command=self.trim_sound)
        self.sound_trim.grid(row=2, column=1, padx=4)
        self.sound_remove = ttk.Button(sound, text="Remove", command=self.remove_sound)
        self.sound_remove.grid(row=2, column=2)
        self.loop = tk.BooleanVar(value=True)
        self.loop_check = ttk.Checkbutton(sound, text="Repeat if shorter than the video", variable=self.loop, command=self._sound_options)
        self.loop_check.grid(row=3, column=0, columnspan=4, sticky="w", pady=(4, 0))
        volume_row = ttk.Frame(sound)
        volume_row.grid(row=4, column=0, columnspan=4, sticky="we")
        ttk.Label(volume_row, text="Volume").pack(side="left")
        self.volume = tk.DoubleVar(value=100)
        self.volume_scale = ttk.Scale(volume_row, from_=0, to=200, variable=self.volume, command=lambda v: self._sound_options())
        self.volume_scale.pack(side="left", fill="x", expand=True, padx=6)
        self.volume_label = ttk.Label(volume_row, width=5)
        self.volume_label.pack(side="left")

        # Subtitles
        subs = ttk.LabelFrame(main, text="Subtitles", padding=6)
        subs.grid(row=2, column=0, columnspan=2, sticky="nsew", **pad)
        self.sub_mode = tk.StringVar(value="off")
        ttk.Radiobutton(subs, text="None", value="off", variable=self.sub_mode, command=self._refresh).grid(row=0, column=0, sticky="w")
        ttk.Radiobutton(subs, text="From speech (Whisper, offline)", value="speech", variable=self.sub_mode, command=self._refresh).grid(row=0, column=1, sticky="w", padx=8)
        ttk.Radiobutton(subs, text="From an .srt file", value="file", variable=self.sub_mode, command=self._refresh).grid(row=0, column=2, sticky="w")
        self.model = tk.StringVar(value="small")
        self.language = tk.StringVar(value="")
        self.srt_file = tk.StringVar(value="")
        self.burn = tk.BooleanVar(value=True)
        self.save_srt = tk.BooleanVar(value=True)
        row = ttk.Frame(subs)
        row.grid(row=1, column=0, columnspan=3, sticky="w", pady=(4, 0))
        ttk.Label(row, text="Model").pack(side="left")
        self.model_box = ttk.Combobox(row, textvariable=self.model, values=list(WHISPER_MODELS), state="readonly", width=9)
        self.model_box.pack(side="left", padx=(4, 12))
        ttk.Label(row, text="Language").pack(side="left")
        self.language_entry = ttk.Entry(row, textvariable=self.language, width=6)
        self.language_entry.pack(side="left", padx=(4, 4))
        ttk.Label(row, text="(blank = detect, or en, hi, ur…)", foreground="gray").pack(side="left", padx=(0, 12))
        self.srt_button = ttk.Button(row, text="Choose .srt…", command=self.choose_srt)
        self.srt_button.pack(side="left")
        row2 = ttk.Frame(subs)
        row2.grid(row=2, column=0, columnspan=3, sticky="w", pady=(4, 0))
        ttk.Checkbutton(row2, text="Draw into the video", variable=self.burn).pack(side="left")
        ttk.Checkbutton(row2, text="Also save an .srt file", variable=self.save_srt).pack(side="left", padx=12)
        self.subs_hint = ttk.Label(subs, foreground="gray")
        self.subs_hint.grid(row=3, column=0, columnspan=3, sticky="w", pady=(4, 0))

        # Export
        export = ttk.Frame(main)
        export.grid(row=3, column=0, columnspan=2, sticky="we", **pad)
        export.columnconfigure(1, weight=1)
        ttk.Label(export, text="Save as").grid(row=0, column=0, sticky="w")
        self.output = tk.StringVar(value=str(Path.home() / "Videos" / "merged.mp4"))
        ttk.Entry(export, textvariable=self.output).grid(row=0, column=1, sticky="we", padx=6)
        ttk.Button(export, text="Browse…", command=self.choose_output).grid(row=0, column=2)
        self.progress = ttk.Progressbar(export, maximum=100)
        self.progress.grid(row=1, column=0, columnspan=3, sticky="we", pady=(8, 2))
        self.status = ttk.Label(export, text="Add videos to start.")
        self.status.grid(row=2, column=0, columnspan=2, sticky="w")
        actions = ttk.Frame(export)
        actions.grid(row=2, column=2, sticky="e")
        self.open_button = ttk.Button(actions, text="Open folder", command=self.open_folder)
        self.cancel_button = ttk.Button(actions, text="Cancel", command=self.cancel)
        self.export_button = ttk.Button(actions, text="Merge & save", command=self.export)
        self.open_button.pack(side="left", padx=4)
        self.cancel_button.pack(side="left", padx=4)
        self.export_button.pack(side="left")

    # -- state to screen --------------------------------------------------

    def _selected(self) -> int | None:
        selection = self.tree.selection()
        return self.tree.index(selection[0]) if selection else None

    def _refresh(self, select: int | None = None):
        if select is None:
            select = self._selected()
        self.tree.delete(*self.tree.get_children())
        for i, item in enumerate(self.items):
            c = item.clip
            trimmed = c.start > 0 or c.end is not None
            trim = f"{fmt(c.start)}–{fmt(item.end)}" if trimmed else ""
            size = ""
            if item.info:
                w, h = (item.info.height, item.info.width) if c.rotate % 180 else (item.info.width, item.info.height)
                size = f"{w}×{h}"
            self.tree.insert("", "end", values=(i + 1, item.name, fmt(item.kept) if item.info else "link", trim, f"{c.rotate}°" if c.rotate else "", size))
        if select is not None and self.items:
            iid = self.tree.get_children()[min(select, len(self.items) - 1)]
            self.tree.selection_set(iid)
            self.tree.see(iid)
        known = [i.kept for i in self.items if i.kept is not None]
        self.total_label.configure(text=f"{len(self.items)} clip(s) · total {fmt(sum(known))}" + (" + links" if len(known) < len(self.items) else ""))

        if self.sound:
            s = self.sound
            part = f"{fmt(s.start)}–{fmt(s.end if s.end is not None else (self.sound_info.duration if self.sound_info else None))}"
            how = "replaces the clips' sound" if self.mute.get() else "mixed with the clips' sound"
            self.sound_label.configure(text=f"{Path(s.path).name if not is_url(s.path) else s.path} · {part} · {how}")
        else:
            self.sound_label.configure(text="No sound." if self.mute.get() else "The clips' own sound.")
        self.volume_label.configure(text=f"{int(self.volume.get())}%")

        mode = self.sub_mode.get()
        self.subs_hint.configure(
            text={
                "off": "",
                "speech": "Turns what is said into captions. The model downloads once (small is about 460 MB); bigger models are better and slower.",
                "file": f"File: {self.srt_file.get() or '(none chosen)'}",
            }[mode]
        )
        self._refresh_buttons()

    def _refresh_buttons(self):
        busy = self.job is not None
        index = self._selected()
        has = index is not None
        state = lambda on: "normal" if on and not busy else "disabled"  # noqa: E731
        self.clip_buttons["add"].configure(state=state(True))
        self.clip_buttons["link"].configure(state=state(True))
        self.clip_buttons["up"].configure(state=state(has and index > 0))
        self.clip_buttons["down"].configure(state=state(has and index < len(self.items) - 1))
        for key in ("trim", "rotate", "remove"):
            self.clip_buttons[key].configure(state=state(has))
        self.sound_add.configure(state=state(True), text="Change sound…" if self.sound else "Add sound…")
        for widget in (self.sound_trim, self.sound_remove, self.loop_check, self.volume_scale):
            widget.configure(state=state(self.sound is not None))
        speech = self.sub_mode.get() == "speech"
        self.model_box.configure(state="readonly" if speech and not busy else "disabled")
        self.language_entry.configure(state=state(speech))
        self.srt_button.configure(state=state(self.sub_mode.get() == "file"))
        self.export_button.configure(state=state(bool(self.items)))
        self.cancel_button.configure(state="normal" if busy else "disabled")
        self.open_button.configure(state="normal" if self.last_output and not busy else "disabled")

    # -- clip actions -------------------------------------------------------

    def _probe(self, path: str) -> tools.MediaInfo | None:
        try:
            return tools.probe(path)
        except tools.ToolError as e:
            messagebox.showerror("Video Merger", str(e))
            return None

    def add_videos(self):
        paths = filedialog.askopenfilenames(title="Add videos", filetypes=VIDEO_TYPES)
        skipped = []
        for path in paths:
            info = self._probe(path)
            if info is None:
                continue
            if not info.has_video or info.duration <= 0:
                skipped.append(Path(path).name)
                continue
            self.items.append(Item(Clip(path), info))
        if skipped:
            messagebox.showwarning("Video Merger", "These have no video picture and were skipped:\n" + "\n".join(skipped))
        self._refresh(select=len(self.items) - 1 if paths else None)

    def add_link(self):
        url = simpledialog.askstring(
            "Add from link",
            "Direct link to a video file (ending in .mp4 or similar).\nOnly use videos you are allowed to use.",
            parent=self.root,
        )
        if not url:
            return
        url = url.strip()
        if not is_url(url):
            messagebox.showerror("Add from link", "That is not an http(s) link.")
            return
        self._run_background("Downloading…", lambda: sources.fetch(url), self._link_downloaded)

    def _link_downloaded(self, path):
        info = self._probe(str(path))
        if info and info.has_video:
            self.items.append(Item(Clip(str(path)), info))
            self._refresh(select=len(self.items) - 1)
            self.status.configure(text=f"Downloaded {Path(path).name}")
        else:
            messagebox.showerror("Add from link", "The downloaded file is not a video.")

    def move(self, step: int):
        i = self._selected()
        if i is None or not 0 <= i + step < len(self.items):
            return
        self.items[i], self.items[i + step] = self.items[i + step], self.items[i]
        self._refresh(select=i + step)

    def trim_clip(self):
        i = self._selected()
        if i is None or self.job:
            return
        item = self.items[i]
        dialog = TrimDialog(self.root, f"Trim {item.name}", item.info.duration if item.info else None, item.clip.start, item.clip.end)
        if dialog.result:
            item.clip.start, item.clip.end = dialog.result
            self._refresh()

    def rotate_clip(self):
        i = self._selected()
        if i is not None:
            self.items[i].clip.rotate = (self.items[i].clip.rotate + 90) % 360
            self._refresh()

    def remove_clip(self):
        i = self._selected()
        if i is not None and not self.job:
            del self.items[i]
            self._refresh(select=min(i, len(self.items) - 1) if self.items else None)

    # -- sound ---------------------------------------------------------------

    def add_sound(self):
        path = filedialog.askopenfilename(title="Take the sound from", filetypes=SOUND_TYPES)
        if not path:
            return
        info = self._probe(path)
        if info is None:
            return
        if not info.has_audio:
            messagebox.showerror("Video Merger", f"{Path(path).name} has no sound.")
            return
        if self.sound is None:
            self.mute.set(True)  # usually you want the new sound instead of the old one
        self.sound, self.sound_info = Sound(path, loop=self.loop.get(), volume=self.volume.get() / 100), info
        self._refresh()

    def trim_sound(self):
        if not self.sound:
            return
        dialog = TrimDialog(self.root, "Trim sound", self.sound_info.duration if self.sound_info else None, self.sound.start, self.sound.end)
        if dialog.result:
            self.sound.start, self.sound.end = dialog.result
            self._refresh()

    def remove_sound(self):
        self.sound = self.sound_info = None
        self.mute.set(False)
        self._refresh()

    def _sound_options(self):
        if self.sound:
            self.sound.loop = self.loop.get()
            self.sound.volume = round(self.volume.get() / 100, 2)
        self.volume_label.configure(text=f"{int(self.volume.get())}%")

    def choose_srt(self):
        path = filedialog.askopenfilename(title="Subtitle file", filetypes=[("Subtitles", "*.srt"), ("All files", "*.*")])
        if path:
            self.srt_file.set(path)
            self._refresh()

    # -- recipes -------------------------------------------------------------

    def to_recipe(self) -> Recipe:
        return Recipe(
            clips=[Clip(i.clip.path, i.clip.start, i.clip.end, i.clip.rotate) for i in self.items],
            output=self.output.get().strip() or "merged.mp4",
            resolution=self.resolution.get(),
            fps=int(self.fps.get()),
            mute_clips=self.mute.get(),
            sound=Sound(**vars(self.sound)) if self.sound else None,
            subtitles=Subtitles(
                mode=self.sub_mode.get(),
                file=self.srt_file.get() or None,
                model=self.model.get(),
                language=self.language.get().strip() or None,
                burn=self.burn.get(),
                save_srt=self.save_srt.get(),
            ),
            base_dir=os.getcwd(),
        )

    def load_recipe(self, recipe: Recipe):
        self.items = []
        for clip in recipe.clips:
            clip.path = recipe.resolve(clip.path)
            info = None
            if not is_url(clip.path):
                if not Path(clip.path).is_file():
                    messagebox.showwarning("Open recipe", f"File not found, skipped:\n{clip.path}")
                    continue
                info = self._probe(clip.path)
            self.items.append(Item(clip, info))
        self.sound = recipe.sound
        self.sound_info = None
        if self.sound:
            self.sound.path = recipe.resolve(self.sound.path)
            if not is_url(self.sound.path) and Path(self.sound.path).is_file():
                self.sound_info = self._probe(self.sound.path)
            self.loop.set(self.sound.loop)
            self.volume.set(self.sound.volume * 100)
        self.resolution.set(recipe.resolution)
        self.fps.set(str(recipe.fps))
        self.mute.set(recipe.mute_clips)
        st = recipe.subtitles
        self.sub_mode.set(st.mode)
        self.srt_file.set(recipe.resolve(st.file) if st.file else "")
        self.model.set(st.model)
        self.language.set(st.language or "")
        self.burn.set(st.burn)
        self.save_srt.set(st.save_srt)
        self.output.set(recipe.resolve(recipe.output))
        self._refresh(select=0 if self.items else None)

    def new(self):
        if self.job:
            return
        self.load_recipe(Recipe(clips=[], output=str(Path.home() / "Videos" / "merged.mp4")))
        self.status.configure(text="Add videos to start.")

    def open_recipe(self, path: str | None = None):
        path = path or filedialog.askopenfilename(title="Open recipe", filetypes=[("Recipes", "*.json"), ("All files", "*.*")])
        if not path:
            return
        try:
            self.load_recipe(load(path))
            self.status.configure(text=f"Opened {Path(path).name}")
        except (RecipeError, OSError) as e:
            messagebox.showerror("Open recipe", str(e))

    def save_recipe(self):
        path = filedialog.asksaveasfilename(title="Save recipe", defaultextension=".json", filetypes=[("Recipes", "*.json")])
        if path:
            self.to_recipe().save(path)
            self.status.configure(text=f"Saved {Path(path).name}. Run it with: VideoMerger run \"{Path(path).name}\"")

    # -- export ---------------------------------------------------------------

    def choose_output(self):
        current = Path(self.output.get())
        path = filedialog.asksaveasfilename(
            title="Save video as", defaultextension=".mp4", initialdir=current.parent, initialfile=current.name, filetypes=[("MP4 video", "*.mp4")]
        )
        if path:
            self.output.set(path)

    def export(self):
        if not self.items or self.job:
            return
        if self.sub_mode.get() == "file" and not self.srt_file.get():
            messagebox.showerror("Subtitles", "Choose an .srt file, or switch subtitles off.")
            return
        recipe = self.to_recipe()
        if Path(recipe.output).exists() and not messagebox.askyesno("Video Merger", f"Replace {Path(recipe.output).name}?"):
            return
        self.job = engine.Job(recipe, on_progress=lambda stage, f: self.events.put(("progress", stage, f)))
        self.progress.configure(value=0)
        self.status.configure(text="Starting…")
        self._refresh_buttons()

        def work():
            try:
                self.events.put(("done", self.job.run()))
            except engine.Cancelled:
                self.events.put(("cancelled",))
            except Exception as e:  # shown to the user, never lost in a thread
                self.events.put(("error", str(e)))

        threading.Thread(target=work, daemon=True).start()

    def cancel(self):
        if self.job:
            self.job.cancel()

    def _run_background(self, message: str, task, on_done):
        self.status.configure(text=message)
        self.progress.configure(mode="indeterminate")
        self.progress.start(15)

        def work():
            try:
                self.events.put(("background", on_done, task()))
            except Exception as e:
                self.events.put(("error", str(e)))

        threading.Thread(target=work, daemon=True).start()

    def _stop_indeterminate(self):
        self.progress.stop()
        self.progress.configure(mode="determinate", value=0)

    def _poll(self):
        try:
            while True:
                event = self.events.get_nowait()
                kind = event[0]
                if kind == "progress":
                    _, stage, fraction = event
                    self.progress.configure(value=fraction * 100)
                    self.status.configure(text=f"{STAGES.get(stage, stage)}… {int(fraction * 100)}%")
                elif kind == "done":
                    result: engine.Result = event[1]
                    self.job = None
                    self.last_output = result.output
                    self.progress.configure(value=100)
                    extra = f" and {Path(result.srt).name}" if result.srt else ""
                    self.status.configure(text=f"Saved {Path(result.output).name}{extra} ({fmt(result.duration)}, {result.width}×{result.height})")
                elif kind == "cancelled":
                    self.job = None
                    self.progress.configure(value=0)
                    self.status.configure(text="Cancelled.")
                elif kind == "error":
                    self.job = None
                    self._stop_indeterminate()
                    self.status.configure(text="Failed.")
                    messagebox.showerror("Video Merger", event[1])
                elif kind == "background":
                    self._stop_indeterminate()
                    event[1](event[2])
                self._refresh_buttons()
        except queue.Empty:
            pass
        self.root.after(100, self._poll)

    def open_folder(self):
        if not self.last_output:
            return
        if os.name == "nt":
            subprocess.run(["explorer", "/select,", os.path.normpath(self.last_output)])
        else:
            subprocess.run(["xdg-open", str(Path(self.last_output).parent)])

    def about(self):
        messagebox.showinfo(
            "About Video Merger",
            f"Video Merger {__version__}\n\n"
            "Merge, trim, rotate and resize videos, swap their sound and add subtitles.\n\n"
            "Automate it from the command line:\n"
            "  VideoMerger run recipe.json\n"
            "  VideoMerger merge a.mp4 b.mp4 -o out.mp4\n\n"
            "Uses FFmpeg (ffmpeg.org) and Whisper (faster-whisper).",
        )


def main(recipe_path: str | None = None) -> None:
    root = tk.Tk()
    try:
        ttk.Style(root).theme_use("vista" if sys.platform == "win32" else "clam")
    except tk.TclError:
        pass
    app = App(root)
    if recipe_path:
        app.open_recipe(recipe_path)
    root.mainloop()
