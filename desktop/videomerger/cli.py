"""Command line. With no arguments, opens the window.

    videomerger run recipe.json            # export what a recipe describes
    videomerger merge a.mp4 b.mp4 -o out.mp4 --sound song.mp3 --subtitles
    videomerger probe clip.mp4             # length, size, sound (JSON)
    videomerger pexels "beach sunset" -n 3 # download free videos from Pexels
    videomerger download URL               # download a direct video link

Progress goes to stderr; the result goes to stdout (JSON with --json).
Exit code 0 on success, 1 on a failed export, 2 on a bad command or recipe.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import asdict
from pathlib import Path

from . import __version__, engine, sources
from . import ffmpeg as tools
from .recipe import RESOLUTIONS, WHISPER_MODELS, RecipeError, from_dict, load

STAGES = {"download": "Downloading", "probe": "Reading clips", "speech": "Making subtitles", "encode": "Exporting"}


def _progress_printer(as_json: bool):
    last = {}

    def report(stage: str, fraction: float) -> None:
        percent = int(fraction * 100)
        if last.get(stage) == percent:
            return
        last[stage] = percent
        if as_json:
            print(json.dumps({"stage": stage, "percent": percent}), file=sys.stderr, flush=True)
        else:
            print(f"\r{STAGES.get(stage, stage)}… {percent}%   ", end="" if percent < 100 else "\n", file=sys.stderr, flush=True)

    return report


def _export(recipe, as_json: bool) -> int:
    try:
        result = engine.run(recipe, _progress_printer(as_json))
    except engine.Cancelled:
        print("Cancelled", file=sys.stderr)
        return 1
    except Exception as e:  # automation always gets one clear result line, never a traceback
        if not isinstance(e, (engine.ExportError, RuntimeError, OSError)):
            e = f"{type(e).__name__}: {e}"
        if as_json:
            print(json.dumps({"ok": False, "error": str(e)}))
        else:
            print(f"Error: {e}", file=sys.stderr)
        return 1
    if as_json:
        print(json.dumps({"ok": True, **asdict(result)}))
    else:
        print(result.output)
        if result.srt:
            print(result.srt)
    return 0


def _cmd_run(args) -> int:
    recipe = load(args.recipe)
    if args.output:
        recipe.output = str(Path(args.output).resolve())
    return _export(recipe, args.json)


def _cmd_merge(args) -> int:
    data = {
        "clips": args.clips,
        "output": args.output,
        "resolution": args.resolution,
        "fps": args.fps,
        "mute_clips": args.mute_clips,
    }
    if args.sound:
        data["sound"] = {"path": args.sound, "start": args.sound_start, "end": args.sound_end, "loop": not args.no_loop, "volume": args.volume, "repeat_video": args.repeat_video}
    if args.srt:
        data["subtitles"] = {"mode": "file", "file": args.srt, "burn": not args.no_burn}
    elif args.subtitles:
        data["subtitles"] = {"mode": "speech", "model": args.model, "language": args.language, "burn": not args.no_burn}
    recipe = from_dict(data, os.getcwd())
    if args.save_recipe:
        recipe.save(args.save_recipe)
    return _export(recipe, args.json)


def _cmd_probe(args) -> int:
    for path in args.files:
        info = tools.probe(path)
        print(json.dumps({"path": path, **asdict(info)}))
    return 0


def _cmd_pexels(args) -> int:
    found = sources.pexels_search(args.query, args.count, orientation=args.orientation)
    if not found:
        print(f"No Pexels videos found for {args.query!r}", file=sys.stderr)
        return 1
    for item in found:
        if not args.no_download:
            item["path"] = str(sources.fetch(item["url"], args.output_dir))
        print(json.dumps(item))
    return 0


def _cmd_download(args) -> int:
    for url in args.urls:
        print(sources.fetch(url, args.output_dir))
    return 0


def _cmd_selftest(args) -> int:
    """Checks that ffmpeg and the speech engine work, without downloading anything."""
    import subprocess

    ok = True
    for name, find in (("ffmpeg", tools.ffmpeg), ("ffprobe", tools.ffprobe)):
        try:
            path = find()
            version = subprocess.run([path, "-version"], capture_output=True, text=True, creationflags=tools.NO_WINDOW).stdout.split("\n")[0]
            print(f"ok    {name}: {version} ({path})")
        except Exception as e:
            ok = False
            print(f"FAIL  {name}: {e}")
    try:
        import ctranslate2
        import numpy
        from faster_whisper.vad import VadOptions, get_speech_timestamps

        get_speech_timestamps(numpy.zeros(16000, dtype=numpy.float32), VadOptions())
        print(f"ok    speech engine: ctranslate2 {ctranslate2.__version__}, voice detection model loads")
    except Exception as e:
        ok = False
        print(f"FAIL  speech engine (subtitles from speech): {e!r}")
    print("All good." if ok else "Some parts are missing.")
    return 0 if ok else 1


def _cmd_gui(args) -> int:
    from .gui import main as gui_main

    gui_main()
    return 0


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="videomerger", description="Merge, trim and edit videos. Without a command, opens the window.")
    p.add_argument("--version", action="version", version=f"Video Merger {__version__}")
    sub = p.add_subparsers(dest="command")

    run = sub.add_parser("run", help="export what a recipe file describes")
    run.add_argument("recipe")
    run.add_argument("-o", "--output", help="override the recipe's output file")
    run.add_argument("--json", action="store_true", help="JSON progress on stderr and a JSON result on stdout")
    run.set_defaults(func=_cmd_run)

    merge = sub.add_parser("merge", help="merge clips without writing a recipe")
    merge.add_argument("clips", nargs="+", help="video files or direct http(s) links, in order")
    merge.add_argument("-o", "--output", default="merged.mp4")
    merge.add_argument("-r", "--resolution", choices=list(RESOLUTIONS) + ["2k"], default="1080p", help="1080p or 1440p (2K)")
    merge.add_argument("--fps", type=int, default=30)
    merge.add_argument("--mute-clips", action="store_true", help="drop the clips' own sound")
    merge.add_argument("--sound", help="take the sound from this video or audio file")
    merge.add_argument("--sound-start", default=None, help="seconds or m:ss into the sound")
    merge.add_argument("--sound-end", default=None)
    merge.add_argument("--no-loop", action="store_true", help="do not repeat a sound that is shorter than the video")
    merge.add_argument("--volume", type=float, default=1.0, help="sound volume, 1 is unchanged")
    merge.add_argument("--repeat-video", action="store_true", help="repeat the clips until the sound ends, if the sound is longer")
    merge.add_argument("--subtitles", action="store_true", help="make subtitles from the speech")
    merge.add_argument("--model", choices=WHISPER_MODELS, default="small", help="Whisper model: bigger is better and slower")
    merge.add_argument("--language", help="speech language such as en or hi (default: detect)")
    merge.add_argument("--srt", help="use this .srt file as the subtitles")
    merge.add_argument("--no-burn", action="store_true", help="only write the .srt, do not draw it into the video")
    merge.add_argument("--save-recipe", help="also save the settings as a recipe file")
    merge.add_argument("--json", action="store_true")
    merge.set_defaults(func=_cmd_merge)

    probe = sub.add_parser("probe", help="show length, size and sound of files")
    probe.add_argument("files", nargs="+")
    probe.set_defaults(func=_cmd_probe)

    pexels = sub.add_parser("pexels", help="find and download free videos from Pexels (needs PEXELS_API_KEY)")
    pexels.add_argument("query")
    pexels.add_argument("-n", "--count", type=int, default=3)
    pexels.add_argument("--orientation", choices=["landscape", "portrait", "square"])
    pexels.add_argument("-d", "--output-dir", help=f"folder for downloads (default {sources.default_dir()})")
    pexels.add_argument("--no-download", action="store_true", help="only list the links")
    pexels.set_defaults(func=_cmd_pexels)

    download = sub.add_parser("download", help="download direct links to video or audio files")
    download.add_argument("urls", nargs="+")
    download.add_argument("-d", "--output-dir")
    download.set_defaults(func=_cmd_download)

    selftest = sub.add_parser("selftest", help="check that ffmpeg and the subtitle engine work")
    selftest.set_defaults(func=_cmd_selftest)

    gui = sub.add_parser("gui", help="open the window")
    gui.set_defaults(func=_cmd_gui)
    return p


def _hide_own_console() -> None:
    """When VideoMerger.exe is double-clicked, Windows opens a console just for it; close that one."""
    if os.name != "nt" or not getattr(sys, "frozen", False):
        return
    import ctypes

    processes = (ctypes.c_uint * 2)()
    if ctypes.windll.kernel32.GetConsoleProcessList(processes, 2) <= 1:
        ctypes.windll.kernel32.FreeConsole()
        # Nothing may write to the closed console (model download progress bars would fail).
        sys.stdout = sys.stderr = open(os.devnull, "w", encoding="utf-8")
        os.environ["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    args = parser().parse_args(argv)
    if not args.command:
        _hide_own_console()
        return _cmd_gui(args)
    try:
        return args.func(args)
    except RecipeError as e:
        return _fail(args, f"Recipe error: {e}", 2)
    except (tools.ToolError, sources.DownloadError) as e:
        return _fail(args, str(e), 1, prefix="Error: ")


def _fail(args, message: str, code: int, prefix: str = "") -> int:
    """With --json, automation gets the same one-line result as a failed export; people get the message on stderr."""
    if getattr(args, "json", False):
        print(json.dumps({"ok": False, "error": message}))
    else:
        print(prefix + message, file=sys.stderr)
    return code
