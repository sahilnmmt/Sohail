"""The recipe: a JSON description of one export, shared by the window and the command line.

Example::

    {
      "output": "merged.mp4",
      "resolution": "1080p",
      "clips": [
        {"path": "intro.mp4", "start": "0:02", "end": "0:10", "rotate": 90},
        {"path": "https://example.com/clip.mp4"}
      ],
      "sound": {"path": "song.mp3", "start": 5, "loop": true},
      "subtitles": {"mode": "speech", "model": "small"}
    }

Relative paths are relative to the recipe file. Times are seconds, or "m:ss" / "h:mm:ss".
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path

# Short side of the output in pixels. Smaller clips are scaled up.
RESOLUTIONS = {"1080p": 1080, "1440p": 1440}
RESOLUTION_ALIASES = {"2k": "1440p", "1440": "1440p", "1080": "1080p", "fhd": "1080p", "full hd": "1080p"}
ROTATIONS = (0, 90, 180, 270)
SUBTITLE_MODES = ("off", "speech", "file")
WHISPER_MODELS = ("tiny", "base", "small", "medium", "large-v3")


class RecipeError(ValueError):
    pass


def parse_time(value, what: str) -> float | None:
    """Seconds from a number or an "m:ss" / "h:mm:ss" string; None stays None."""
    if value is None or value == "":
        return None
    if isinstance(value, bool):
        raise RecipeError(f"{what}: expected a time, got {value!r}")
    if isinstance(value, (int, float)):
        seconds = float(value)
    else:
        try:
            seconds = 0.0
            for part in str(value).strip().split(":"):
                seconds = seconds * 60 + float(part)
        except ValueError:
            raise RecipeError(f"{what}: {value!r} is not a time (use seconds or m:ss)") from None
    if seconds < 0:
        raise RecipeError(f"{what}: time cannot be negative")
    return seconds


def is_url(source: str) -> bool:
    return source.startswith(("http://", "https://"))


@dataclass
class Clip:
    path: str
    start: float = 0.0
    end: float | None = None
    rotate: int = 0


@dataclass
class Sound:
    path: str
    start: float = 0.0
    end: float | None = None
    loop: bool = True
    volume: float = 1.0


@dataclass
class Subtitles:
    mode: str = "off"
    """off; speech (made from the output's sound with Whisper); file (an existing .srt)."""
    file: str | None = None
    model: str = "small"
    language: str | None = None
    """Two-letter code such as "en"; None detects it."""
    burn: bool = True
    """Draw the subtitles into the picture."""
    save_srt: bool = True
    """Also write an .srt file next to the output."""


@dataclass
class Recipe:
    clips: list[Clip]
    output: str = "merged.mp4"
    resolution: str = "1080p"
    fps: int = 30
    mute_clips: bool = False
    """Drop the clips' own sound. An added sound is still used."""
    sound: Sound | None = None
    subtitles: Subtitles = field(default_factory=Subtitles)
    base_dir: str = "."
    """Folder that relative paths start from. Not saved."""

    def resolve(self, path: str) -> str:
        if is_url(path):
            return path
        p = Path(path).expanduser()
        return str(p if p.is_absolute() else (Path(self.base_dir) / p).resolve())

    @property
    def short_side(self) -> int:
        return RESOLUTIONS[self.resolution]

    def to_dict(self) -> dict:
        data = asdict(self)
        data.pop("base_dir")
        return data

    def save(self, path: str | Path) -> None:
        Path(path).write_text(json.dumps(self.to_dict(), indent=2) + "\n", encoding="utf-8")


def _get(data: dict, key: str, kind, default, what: str):
    value = data.get(key, default)
    if value is None:
        return None
    number = isinstance(value, (int, float)) and not isinstance(value, bool)
    if kind is float and number:
        return float(value)
    if kind is int and number and float(value).is_integer():
        return int(value)
    if kind in (bool, str) and isinstance(value, kind):
        return value
    raise RecipeError(f"{what}.{key}: expected {kind.__name__}, got {value!r}")


def _unknown(data: dict, allowed: set[str], what: str) -> None:
    extra = set(data) - allowed
    if extra:
        raise RecipeError(f"{what}: unknown field(s) {', '.join(sorted(extra))}")


def from_dict(data: dict, base_dir: str | Path = ".") -> Recipe:
    if not isinstance(data, dict):
        raise RecipeError("recipe: expected a JSON object")
    _unknown(data, {"clips", "output", "resolution", "fps", "mute_clips", "sound", "subtitles"}, "recipe")

    raw_clips = data.get("clips")
    if not isinstance(raw_clips, list) or not raw_clips:
        raise RecipeError("recipe.clips: give at least one clip")
    clips = []
    for i, raw in enumerate(raw_clips):
        what = f"clips[{i}]"
        if isinstance(raw, str):
            raw = {"path": raw}
        if not isinstance(raw, dict) or not isinstance(raw.get("path"), str) or not raw["path"]:
            raise RecipeError(f"{what}: needs a \"path\" (file or http(s) URL)")
        _unknown(raw, {"path", "start", "end", "rotate"}, what)
        clip = Clip(
            path=raw["path"],
            start=parse_time(raw.get("start"), f"{what}.start") or 0.0,
            end=parse_time(raw.get("end"), f"{what}.end"),
            rotate=_get(raw, "rotate", int, 0, what),
        )
        if clip.rotate not in ROTATIONS:
            raise RecipeError(f"{what}.rotate: use 0, 90, 180 or 270 (clockwise)")
        if clip.end is not None and clip.end <= clip.start:
            raise RecipeError(f"{what}: end must be after start")
        clips.append(clip)

    resolution = str(data.get("resolution", "1080p")).strip().lower()
    resolution = RESOLUTION_ALIASES.get(resolution, resolution)
    if resolution not in RESOLUTIONS:
        raise RecipeError("recipe.resolution: use 1080p or 1440p (2K); output is never below 1080p")
    fps = _get(data, "fps", int, 30, "recipe")
    if not 1 <= fps <= 120:
        raise RecipeError("recipe.fps: use 1 to 120")

    sound = None
    if data.get("sound") is not None:
        raw = data["sound"]
        if isinstance(raw, str):
            raw = {"path": raw}
        if not isinstance(raw, dict) or not isinstance(raw.get("path"), str) or not raw["path"]:
            raise RecipeError("recipe.sound: needs a \"path\" (video or audio file, or URL)")
        _unknown(raw, {"path", "start", "end", "loop", "volume"}, "sound")
        sound = Sound(
            path=raw["path"],
            start=parse_time(raw.get("start"), "sound.start") or 0.0,
            end=parse_time(raw.get("end"), "sound.end"),
            loop=_get(raw, "loop", bool, True, "sound"),
            volume=_get(raw, "volume", float, 1.0, "sound"),
        )
        if sound.end is not None and sound.end <= sound.start:
            raise RecipeError("sound: end must be after start")
        if not 0 <= sound.volume <= 10:
            raise RecipeError("sound.volume: use 0 to 10 (1 is unchanged)")

    raw = data.get("subtitles") or {}
    if not isinstance(raw, dict):
        raise RecipeError("recipe.subtitles: expected an object")
    _unknown(raw, {"mode", "file", "model", "language", "burn", "save_srt"}, "subtitles")
    subtitles = Subtitles(
        mode=_get(raw, "mode", str, "off", "subtitles"),
        file=_get(raw, "file", str, None, "subtitles"),
        model=_get(raw, "model", str, "small", "subtitles"),
        language=_get(raw, "language", str, None, "subtitles") or None,
        burn=_get(raw, "burn", bool, True, "subtitles"),
        save_srt=_get(raw, "save_srt", bool, True, "subtitles"),
    )
    if subtitles.mode not in SUBTITLE_MODES:
        raise RecipeError(f"subtitles.mode: use one of {', '.join(SUBTITLE_MODES)}")
    if subtitles.mode == "file" and not subtitles.file:
        raise RecipeError("subtitles: mode \"file\" needs \"file\": \"captions.srt\"")
    if subtitles.model not in WHISPER_MODELS:
        raise RecipeError(f"subtitles.model: use one of {', '.join(WHISPER_MODELS)}")

    output = data.get("output", "merged.mp4")
    if not isinstance(output, str) or not output:
        raise RecipeError("recipe.output: expected a file name")

    return Recipe(
        clips=clips,
        output=output,
        resolution=resolution,
        fps=fps,
        mute_clips=_get(data, "mute_clips", bool, False, "recipe"),
        sound=sound,
        subtitles=subtitles,
        base_dir=str(Path(base_dir).resolve()),
    )


def load(path: str | Path) -> Recipe:
    path = Path(path)
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except json.JSONDecodeError as e:
        raise RecipeError(f"{path.name}: not valid JSON ({e})") from None
    except UnicodeDecodeError:
        raise RecipeError(f"{path.name}: not a text file (save it as UTF-8)") from None
    except FileNotFoundError:
        raise RecipeError(f"Recipe file not found: {path.resolve()}") from None
    except OSError as e:
        raise RecipeError(f"Cannot read recipe {path}: {e.strerror or e}") from None
    return from_dict(data, path.parent)
