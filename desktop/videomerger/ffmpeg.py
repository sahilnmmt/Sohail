"""Finding and running ffmpeg / ffprobe."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

# Keeps ffmpeg from opening console windows when started from the window app.
NO_WINDOW = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0


class ToolError(RuntimeError):
    pass


def _find(name: str) -> str:
    exe = name + (".exe" if os.name == "nt" else "")
    override = os.environ.get("VIDEOMERGER_" + name.upper())
    candidates = [override] if override else []
    if getattr(sys, "frozen", False):
        # The Windows build ships ffmpeg next to VideoMerger.exe.
        here = Path(sys.executable).parent
        candidates += [str(here / exe), str(here / "ffmpeg" / exe)]
    candidates.append(shutil.which(name))
    for c in candidates:
        if c and Path(c).is_file():
            return c
    raise ToolError(f"{name} not found. Install FFmpeg and put it on PATH, or set VIDEOMERGER_{name.upper()}.")


def ffmpeg() -> str:
    return _find("ffmpeg")


def ffprobe() -> str:
    return _find("ffprobe")


@dataclass
class MediaInfo:
    duration: float
    width: int
    """Shown size, with the file's rotation already applied (ffmpeg rotates on decode)."""
    height: int
    has_video: bool
    has_audio: bool


def probe(path: str) -> MediaInfo:
    result = subprocess.run(
        [ffprobe(), "-v", "error", "-show_streams", "-show_format", "-of", "json", path],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=NO_WINDOW,
    )
    if result.returncode != 0:
        raise ToolError(f"Cannot read {Path(path).name}: {result.stderr.strip() or 'ffprobe failed'}")
    data = json.loads(result.stdout or "{}")
    streams = data.get("streams", [])
    # Cover art in music files shows up as a one-frame video stream; ignore it.
    video = next(
        (s for s in streams if s.get("codec_type") == "video" and not s.get("disposition", {}).get("attached_pic")),
        None,
    )
    audio = next((s for s in streams if s.get("codec_type") == "audio"), None)

    duration = 0.0
    for candidate in (data.get("format", {}).get("duration"), (video or {}).get("duration"), (audio or {}).get("duration")):
        try:
            duration = float(candidate)
            break
        except (TypeError, ValueError):
            continue

    width = height = 0
    if video:
        width, height = int(video.get("width", 0)), int(video.get("height", 0))
        if _rotation(video) % 180:
            width, height = height, width
    return MediaInfo(duration, width, height, video is not None, audio is not None)


def _rotation(stream: dict) -> int:
    for side in stream.get("side_data_list", []):
        if "rotation" in side:
            return int(round(float(side["rotation"]))) % 360
    try:
        return int(stream.get("tags", {}).get("rotate", 0)) % 360
    except ValueError:
        return 0
