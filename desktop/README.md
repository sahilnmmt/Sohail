# Video Merger for Windows

The desktop version of the Android Video Merger, with a window **and** a
command line for automation.

- **Merge** any number of videos, in the order you choose (local files or direct links).
- **Trim** and **rotate** each clip.
- **Output size:** 1080p (Full HD) or 1440p (2K), and frames per second. Smaller clips are scaled up, so output is never below 1080p. The first clip sets landscape or portrait; other shapes get black bars.
- **Sound from another file:** take the sound from another video or an audio file (MP3, M4A, WAV…), trim it, repeat it, set its volume, and replace or mix with the clips' own sound.
- **Subtitles from speech:** Whisper listens to the finished video's sound and writes captions, offline. They are drawn into the video and/or saved as an `.srt` file. You can also use your own `.srt`.
- **Free stock videos:** search and download from [Pexels](https://www.pexels.com/api/) (free API key).

## Install
1. Download **https://github.com/sahilnmmt/Sohail/releases/download/video-merger-windows-latest/VideoMerger-windows.zip**
2. Unzip it anywhere, for example `C:\VideoMerger`.
3. Double-click **VideoMerger.exe**. If Windows SmartScreen warns about an unknown app, choose *More info → Run anyway* (the app is not code-signed).

FFmpeg is included. The first time you use subtitles from speech, the Whisper
model downloads once (small: about 460 MB) into your user folder.

Check an install with `VideoMerger.exe selftest`.

## Automation (command line)
Open *Command Prompt* or *PowerShell* in the VideoMerger folder (or add it to `PATH`).

```bat
:: merge clips, take the sound from a song, add subtitles from speech
VideoMerger merge intro.mp4 "C:\clips\talk.mp4" https://example.com/b-roll.mp4 ^
    -o final.mp4 -r 1440p --sound song.mp3 --volume 0.3 --subtitles --model small

:: everything in a recipe file (see below)
VideoMerger run recipe.json

:: machine-readable progress (stderr) and result (stdout)
VideoMerger run recipe.json --json

:: free stock videos from Pexels (set PEXELS_API_KEY first)
VideoMerger pexels "sunset beach" -n 3 --orientation landscape -d downloads

:: details of a file: length, size, has sound
VideoMerger probe clip.mp4
```

`--json` prints `{"ok": true, "output": "...", "srt": "...", "duration": 12.5, "width": 1280, "height": 720}`,
or `{"ok": false, "error": "..."}`. Exit code: 0 done, 1 export failed, 2 bad recipe.

### Recipe file
Make one with *File → Save recipe…* in the window, with `merge … --save-recipe recipe.json`, or by hand:

```json
{
  "output": "my-video.mp4",
  "resolution": "1080p",
  "fps": 30,
  "mute_clips": false,
  "clips": [
    {"path": "clip1.mp4", "start": "0:02", "end": "0:12"},
    {"path": "clip2.mp4", "rotate": 90},
    {"path": "https://example.com/videos/clip3.mp4"}
  ],
  "sound": {"path": "song.mp3", "start": 0, "loop": true, "volume": 0.3},
  "subtitles": {"mode": "speech", "model": "small", "language": null, "burn": true, "save_srt": true}
}
```

| Field | Meaning |
|---|---|
| `clips` | In order. `path` is a file (relative to the recipe) or a direct `http(s)` link to a video file. `start`/`end` in seconds or `m:ss`. `rotate`: 0, 90, 180, 270 clockwise. |
| `resolution` | `1080p` (default) or `1440p` (also written `2k`) |
| `mute_clips` | `true` drops the clips' own sound |
| `sound` | Optional. Sound from another video or audio file; `loop` repeats it if shorter than the video; `volume` 1 = unchanged. It always stops when the video ends. |
| `subtitles.mode` | `off`, `speech` (Whisper; `model`: tiny, base, small, medium, large-v3; `language`: e.g. `en`, `hi`, `ur`, or null to detect) or `file` (with `"file": "captions.srt"`) |
| `subtitles.burn` / `save_srt` | Draw them into the video / also write `output.srt` |

Links are downloaded once into `%LOCALAPPDATA%\VideoMerger\downloads`.

### With Claude (Cowork) on your laptop
Cowork can browse a page you choose, download the videos you are allowed to
use, write a recipe and run `VideoMerger run recipe.json --json`, then check
the result. A good first request:

> Open *page*. Download the videos on it into `C:\VideoMerger\work`. Write `C:\VideoMerger\work\recipe.json`
> that merges them in page order at 1080p with subtitles from speech, and run
> `C:\VideoMerger\VideoMerger.exe run C:\VideoMerger\work\recipe.json --json`. Tell me where the result is.

Only use videos you have the right to use: your own, ones with permission, or
free-licence sources such as Pexels and Pixabay. Many sites (YouTube,
Instagram, TikTok…) do not allow downloading in their terms.

## Run from source (any OS)
Needs Python 3.10+ and FFmpeg on `PATH`.

```sh
cd desktop
pip install -r requirements.txt    # only needed for subtitles from speech
python -m videomerger              # window
python -m videomerger run examples/recipe.json
pip install -r requirements-dev.txt && python -m pytest tests
```

## Code
| File | What it does |
|---|---|
| `videomerger/recipe.py` | Recipe format, loading and checking |
| `videomerger/engine.py` | Builds the FFmpeg filter graph (trim, rotate, fit, join, sound, subtitles) and runs it |
| `videomerger/subtitles.py` | Whisper speech to captions, SRT output |
| `videomerger/sources.py` | Direct-link downloads and Pexels search |
| `videomerger/ffmpeg.py` | Finds FFmpeg, reads file details |
| `videomerger/gui.py` | The window |
| `videomerger/cli.py` | Command line |

The Windows build bundles an FFmpeg GPL build from [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds); its licence is in `FFmpeg-LICENSE.txt`.
