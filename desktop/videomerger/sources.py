"""Getting videos from the internet: direct file links, and the free Pexels video library.

Only download videos you are allowed to use. Pexels videos are free to use
(https://www.pexels.com/license/); most other sites' videos are not.
"""

from __future__ import annotations

import hashlib
import json
import os
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Callable

USER_AGENT = "VideoMerger/1.0"
VIDEO_EXTENSIONS = {".mp4", ".mov", ".m4v", ".webm", ".mkv", ".avi", ".mp3", ".m4a", ".wav", ".aac", ".ogg", ".flac"}


class DownloadError(RuntimeError):
    pass


def default_dir() -> Path:
    base = os.environ.get("LOCALAPPDATA") or os.path.join(Path.home(), ".cache")
    return Path(base) / "VideoMerger" / "downloads"


def _file_name(url: str) -> str:
    path = urllib.parse.urlparse(url).path
    name = Path(urllib.parse.unquote(path)).name
    digest = hashlib.sha1(url.encode()).hexdigest()[:10]
    stem, ext = os.path.splitext(name)
    if ext.lower() not in VIDEO_EXTENSIONS:
        stem, ext = stem or "download", ".mp4"
    safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in stem)[:60] or "download"
    return f"{safe}-{digest}{ext}"


def fetch(
    url: str,
    folder: str | Path | None = None,
    check_cancel: Callable[[], None] | None = None,
    on_progress: Callable[[float], None] | None = None,
) -> Path:
    """Downloads a direct link to a video or audio file, once; later calls reuse the file."""
    folder = Path(folder) if folder else default_dir()
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / _file_name(url)
    if target.is_file() and target.stat().st_size > 0:
        return target
    partial = target.with_suffix(target.suffix + ".part")
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=60) as response, open(partial, "wb") as out:
            kind = response.headers.get("Content-Type", "")
            if kind.startswith("text/html"):
                raise DownloadError(
                    f"{url} is a web page, not a video file. Open the page and copy the video's own link (ending in .mp4)."
                )
            size = int(response.headers.get("Content-Length") or 0)
            done = 0
            while chunk := response.read(1 << 20):
                if check_cancel:
                    check_cancel()
                out.write(chunk)
                done += len(chunk)
                if on_progress and size:
                    on_progress(done / size)
    except DownloadError:
        partial.unlink(missing_ok=True)
        raise
    except OSError as e:
        partial.unlink(missing_ok=True)
        raise DownloadError(f"Download failed for {url}: {e}") from e
    except BaseException:
        partial.unlink(missing_ok=True)
        raise
    partial.replace(target)
    return target


def pexels_search(query: str, count: int = 3, api_key: str | None = None, orientation: str | None = None) -> list[dict]:
    """Finds free videos on Pexels. Returns [{"url", "page", "author", "duration", "width", "height"}].

    Needs a free API key from https://www.pexels.com/api/ (PEXELS_API_KEY).
    """
    api_key = api_key or os.environ.get("PEXELS_API_KEY")
    if not api_key:
        raise DownloadError("Set PEXELS_API_KEY (free at https://www.pexels.com/api/) to search Pexels")
    params = {"query": query, "per_page": max(1, min(count, 80))}
    if orientation:
        params["orientation"] = orientation
    request = urllib.request.Request(
        "https://api.pexels.com/videos/search?" + urllib.parse.urlencode(params),
        headers={"Authorization": api_key, "User-Agent": USER_AGENT},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = json.load(response)
    except OSError as e:
        raise DownloadError(f"Pexels search failed: {e}") from e

    results = []
    for video in data.get("videos", [])[:count]:
        files = [f for f in video.get("video_files", []) if f.get("file_type") == "video/mp4" and f.get("link")]
        if not files:
            continue
        # The largest file that is at most 1080p on its short side.
        fitting = [f for f in files if min(f.get("width") or 0, f.get("height") or 0) <= 1080] or files
        best = max(fitting, key=lambda f: (f.get("width") or 0) * (f.get("height") or 0))
        results.append(
            {
                "url": best["link"],
                "page": video.get("url"),
                "author": (video.get("user") or {}).get("name"),
                "duration": video.get("duration"),
                "width": best.get("width"),
                "height": best.get("height"),
            }
        )
    return results
