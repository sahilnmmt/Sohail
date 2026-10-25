"""Subtitles from speech with Whisper (faster-whisper, runs offline on the CPU), written as SRT."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Iterable

MAX_CHARS = 42
MAX_SECONDS = 5.0
PAUSE = 0.8
"""A silence this long (seconds) starts a new caption."""


@dataclass
class Cue:
    start: float
    end: float
    text: str


def group_words(words: Iterable[tuple[float, float, str]]) -> list[Cue]:
    """Joins timed words into captions of at most MAX_CHARS characters and MAX_SECONDS seconds,
    breaking after sentence ends and at pauses."""
    cues: list[Cue] = []
    current: list[tuple[float, float, str]] = []

    def flush() -> None:
        if current:
            text = " ".join(w for _, _, w in current)
            cues.append(Cue(current[0][0], current[-1][1], text))
            current.clear()

    for start, end, word in words:
        word = word.strip()
        if not word:
            continue
        if current:
            length = len(" ".join(w for _, _, w in current)) + 1 + len(word)
            if (
                length > MAX_CHARS
                or end - current[0][0] > MAX_SECONDS
                or start - current[-1][1] > PAUSE
                or current[-1][2][-1] in ".?!"
            ):
                flush()
        current.append((start, max(end, start), word))
    flush()
    return cues


def _timestamp(seconds: float) -> str:
    ms = int(round(max(0.0, seconds) * 1000))
    h, ms = divmod(ms, 3_600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def to_srt(cues: list[Cue]) -> str:
    blocks = []
    for i, cue in enumerate(cues, 1):
        end = max(cue.end, cue.start + 0.3)
        blocks.append(f"{i}\n{_timestamp(cue.start)} --> {_timestamp(end)}\n{cue.text}\n")
    return "\n".join(blocks)


def transcribe(
    wav_path: str,
    model_name: str = "small",
    language: str | None = None,
    on_progress: Callable[[float], None] | None = None,
    check_cancel: Callable[[], None] | None = None,
) -> list[Cue]:
    """Runs Whisper on a 16 kHz mono WAV. The model downloads once (tiny 75 MB ... large-v3 3 GB)."""
    try:
        from faster_whisper import WhisperModel
    except ImportError as e:  # pragma: no cover - only without the optional dependency
        raise RuntimeError("Subtitles from speech need faster-whisper: pip install faster-whisper") from e

    model = WhisperModel(model_name, device="cpu", compute_type="int8")
    segments, info = model.transcribe(wav_path, language=language, vad_filter=True, word_timestamps=True)
    words: list[tuple[float, float, str]] = []
    for segment in segments:  # a generator: transcription happens while iterating
        if check_cancel:
            check_cancel()
        if segment.words:
            words += [(w.start, w.end, w.word) for w in segment.words]
        else:
            words.append((segment.start, segment.end, segment.text))
        if on_progress and info.duration:
            on_progress(min(1.0, segment.end / info.duration))
    return group_words(words)
