"""Builds and runs the ffmpeg commands for one recipe."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from . import ffmpeg as tools
from . import sources, subtitles
from .recipe import Recipe, RecipeError, is_url

SAMPLE_RATE = 48000
AUDIO_FORMAT = f"aresample={SAMPLE_RATE},aformat=sample_fmts=fltp:channel_layouts=stereo"

# stage is one of: download, probe, speech, encode. fraction is 0..1.
Progress = Callable[[str, float], None]


class Cancelled(Exception):
    pass


class ExportError(RuntimeError):
    pass


@dataclass
class Segment:
    path: str
    start: float
    duration: float
    rotate: int
    info: tools.MediaInfo


@dataclass
class SoundSegment:
    path: str
    start: float
    end: float
    loop: bool
    volume: float


@dataclass
class Result:
    output: str
    srt: str | None
    duration: float
    width: int
    height: int


def output_size(width: int, height: int, short_side: int) -> tuple[int, int]:
    """The first clip sets the shape (landscape or portrait); short_side sets its size. Encoders need even sizes."""

    def even(v: float) -> int:
        v = int(round(v))
        return max(2, v - v % 2)

    scale = short_side / min(width, height)
    return even(width * scale), even(height * scale)


def _rotate_filter(degrees: int) -> str:
    return {0: "", 90: "transpose=clock,", 180: "hflip,vflip,", 270: "transpose=cclock,"}[degrees]


def _escape_style(value: str) -> str:
    return value.replace("'", "")


class Job:
    """One export. run() blocks; cancel() may be called from another thread."""

    def __init__(self, recipe: Recipe, on_progress: Progress | None = None, download_dir: str | None = None):
        self.recipe = recipe
        self.on_progress = on_progress or (lambda stage, fraction: None)
        self.download_dir = download_dir
        self._cancel = threading.Event()
        self._process: subprocess.Popen | None = None
        self.segments: list[Segment] = []
        self.sound: SoundSegment | None = None
        self.size = (0, 0)

    def cancel(self) -> None:
        self._cancel.set()
        process = self._process
        if process and process.poll() is None:
            process.kill()

    @property
    def total(self) -> float:
        return sum(s.duration for s in self.segments)

    @property
    def clip_audio(self) -> bool:
        return not self.recipe.mute_clips

    @property
    def has_audio(self) -> bool:
        return self.clip_audio or self.sound is not None

    # -- preparing -------------------------------------------------------

    def _local(self, source: str) -> str:
        if is_url(source):
            return str(sources.fetch(source, self.download_dir, self._check, lambda f: self.on_progress("download", f)))
        path = self.recipe.resolve(source)
        if not Path(path).is_file():
            raise ExportError(f"File not found: {path}")
        return path

    def prepare(self) -> None:
        """Downloads URLs, reads every input and works out the output size."""
        r = self.recipe
        self.segments = []
        for i, clip in enumerate(r.clips):
            self._check()
            self.on_progress("probe", i / len(r.clips))
            path = self._local(clip.path)
            info = tools.probe(path)
            name = Path(path).name
            if not info.has_video:
                raise ExportError(f"{name} has no video picture; use it as the sound instead")
            if info.duration <= 0:
                raise ExportError(f"{name}: cannot tell how long it is")
            end = min(clip.end, info.duration) if clip.end is not None else info.duration
            if clip.start >= end:
                raise ExportError(f"{name}: start {clip.start:.1f}s is past the end ({info.duration:.1f}s)")
            self.segments.append(Segment(path, clip.start, end - clip.start, clip.rotate, info))

        self.sound = None
        if r.sound:
            path = self._local(r.sound.path)
            info = tools.probe(path)
            if not info.has_audio:
                raise ExportError(f"{Path(path).name} has no sound")
            end = min(r.sound.end, info.duration) if r.sound.end is not None else info.duration
            if r.sound.start >= end:
                raise ExportError(f"Sound: start {r.sound.start:.1f}s is past its end ({info.duration:.1f}s)")
            self.sound = SoundSegment(path, r.sound.start, end, r.sound.loop, r.sound.volume)

        first = self.segments[0]
        w, h = (first.info.height, first.info.width) if first.rotate % 180 else (first.info.width, first.info.height)
        self.size = output_size(w, h, r.short_side)

    # -- ffmpeg graph -----------------------------------------------------

    def graph(self, video: bool = True, subtitle_file: str | None = None) -> tuple[list[str], str, list[str]]:
        """ffmpeg input arguments, the -filter_complex graph, and -map arguments.

        video=False builds only the sound (used to make subtitles from speech).
        """
        width, height = self.size
        fps = self.recipe.fps
        args: list[str] = []
        chains: list[str] = []
        concat_in = ""
        for i, seg in enumerate(self.segments):
            args += ["-ss", f"{seg.start:.3f}", "-t", f"{seg.duration:.3f}", "-i", seg.path]
            d = f"{seg.duration:.3f}"
            if video:
                chains.append(
                    f"[{i}:v:0]{_rotate_filter(seg.rotate)}"
                    f"scale={width}:{height}:force_original_aspect_ratio=decrease:flags=lanczos,"
                    f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,"
                    f"fps={fps},format=yuv420p,trim=duration={d},setpts=PTS-STARTPTS[v{i}]"
                )
                concat_in += f"[v{i}]"
            if self.clip_audio:
                source = f"[{i}:a:0]" if seg.info.has_audio else f"anullsrc=channel_layout=stereo:sample_rate={SAMPLE_RATE},"
                # Pad or cut each clip's sound to exactly its picture's length, so they stay in sync.
                chains.append(f"{source}{AUDIO_FORMAT},apad,atrim=duration={d},asetpts=N/SR/TB[a{i}]")
                concat_in += f"[a{i}]"

        n = len(self.segments)
        outs = ("[vcat]" if video else "") + ("[acat]" if self.clip_audio else "")
        if outs:
            chains.append(f"{concat_in}concat=n={n}:v={int(video)}:a={int(self.clip_audio)}{outs}")

        total = f"{self.total:.3f}"
        if self.sound:
            s = self.sound
            idx = n
            args += ["-i", s.path]
            loop = f",aloop=loop=-1:size={max(1, int((s.end - s.start) * SAMPLE_RATE))}" if s.loop else ""
            chains.append(
                f"[{idx}:a:0]{AUDIO_FORMAT},atrim=start={s.start:.3f}:end={s.end:.3f},asetpts=N/SR/TB,"
                f"volume={s.volume:g}{loop},apad,atrim=duration={total},asetpts=N/SR/TB[snd]"
            )
            if self.clip_audio:
                chains.append("[acat][snd]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[aout]")
            else:
                chains.append("[snd]anull[aout]")
        elif self.clip_audio:
            chains.append("[acat]anull[aout]")

        maps: list[str] = []
        if video:
            if subtitle_file:
                portrait = height > width
                style = ",".join(
                    [
                        f"Fontsize={9 if portrait else 14}",
                        "Outline=1.5",
                        "Shadow=0",
                        "MarginV=16",
                        "PrimaryColour=&H00FFFFFF",
                        "OutlineColour=&H00000000",
                    ]
                )
                chains.append(f"[vcat]subtitles=filename={subtitle_file}:force_style='{_escape_style(style)}'[vout]")
            else:
                chains.append("[vcat]null[vout]")
            maps += ["-map", "[vout]"]
        if self.has_audio:
            maps += ["-map", "[aout]"]
        return args, ";".join(chains), maps

    # -- running ----------------------------------------------------------

    def _check(self) -> None:
        if self._cancel.is_set():
            raise Cancelled()

    def _ffmpeg(self, args: list[str], stage: str, cwd: str | None = None) -> None:
        self._check()
        command = [tools.ffmpeg(), "-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-nostats", "-progress", "pipe:1"] + args
        total_us = max(1.0, self.total * 1_000_000)
        errors: list[str] = []
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=cwd,
            creationflags=tools.NO_WINDOW,
        )
        self._process = process
        drain = threading.Thread(target=lambda: errors.extend(process.stderr), daemon=True)
        drain.start()
        for line in process.stdout:
            key, _, value = line.strip().partition("=")
            if key == "out_time_us" and value.isdigit():
                self.on_progress(stage, min(1.0, int(value) / total_us))
        process.wait()
        drain.join()
        self._process = None
        self._check()
        if process.returncode != 0:
            message = "".join(errors).strip().splitlines()
            raise ExportError("ffmpeg failed: " + (message[-1] if message else f"exit code {process.returncode}"))
        self.on_progress(stage, 1.0)

    def run(self) -> Result:
        r = self.recipe
        self.prepare()
        output = Path(r.resolve(r.output))
        if output.suffix.lower() != ".mp4":
            output = output.with_suffix(".mp4")
        inputs = [s.path for s in self.segments] + ([self.sound.path] if self.sound else [])
        if output.exists() and any(os.path.samefile(output, path) for path in inputs):
            raise ExportError(f"The output {output.name} is also one of the inputs; choose another output name")
        output.parent.mkdir(parents=True, exist_ok=True)

        work = tempfile.mkdtemp(prefix="videomerger-")
        try:
            cues = None
            st = r.subtitles
            if st.mode == "speech":
                if not self.has_audio:
                    raise ExportError("Subtitles from speech need sound, but all sound is removed")
                wav = os.path.join(work, "speech.wav")
                args, graph, maps = self.graph(video=False)
                self._ffmpeg(args + ["-filter_complex", graph] + maps + ["-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", wav], "speech")
                cues = subtitles.transcribe(wav, st.model, st.language, lambda f: self.on_progress("speech", f), self._check)
                srt_text = subtitles.to_srt(cues)
            elif st.mode == "file":
                srt_path = r.resolve(st.file)
                if not Path(srt_path).is_file():
                    raise ExportError(f"Subtitle file not found: {srt_path}")
                srt_text = Path(srt_path).read_text(encoding="utf-8-sig", errors="replace")
            else:
                srt_text = None

            subtitle_file = None
            if srt_text is not None and st.burn and srt_text.strip():
                Path(work, "subs.srt").write_text(srt_text, encoding="utf-8")
                subtitle_file = "subs.srt"  # ffmpeg runs in `work`, so no Windows path escaping is needed

            partial = os.path.join(work, "out.mp4")
            args, graph, maps = self.graph(video=True, subtitle_file=subtitle_file)
            # High quality for 1080p/2K: CRF 18 is close to visually lossless.
            encode = ["-c:v", "libx264", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p"]
            if self.has_audio:
                encode += ["-c:a", "aac", "-b:a", "192k"]
            self._ffmpeg(args + ["-filter_complex", graph] + maps + encode + ["-movflags", "+faststart", partial], "encode", cwd=work)
            shutil.move(partial, output)

            srt_out = None
            if srt_text is not None and st.save_srt:
                srt_out = str(output.with_suffix(".srt"))
                Path(srt_out).write_text(srt_text, encoding="utf-8")
            return Result(str(output), srt_out, self.total, *self.size)
        finally:
            shutil.rmtree(work, ignore_errors=True)


def run(recipe: Recipe, on_progress: Progress | None = None) -> Result:
    try:
        return Job(recipe, on_progress).run()
    except (tools.ToolError, sources.DownloadError, RecipeError) as e:
        raise ExportError(str(e)) from e
