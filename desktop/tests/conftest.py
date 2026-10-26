import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from videomerger import ffmpeg as tools  # noqa: E402


def make_clip(path: Path, seconds: float, size: str = "640x360", audio: bool = True, rotate: int | None = None, tone: int = 440) -> Path:
    """A test-pattern video, optionally with a sine tone and rotation metadata."""
    cmd = [tools.ffmpeg(), "-v", "error", "-y", "-f", "lavfi", "-i", f"testsrc2=size={size}:rate=30:duration={seconds}"]
    if audio:
        cmd += ["-f", "lavfi", "-i", f"sine=frequency={tone}:sample_rate=44100:duration={seconds}"]
    cmd += ["-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p"]
    if audio:
        cmd += ["-c:a", "aac", "-shortest"]
    cmd.append(str(path))
    subprocess.run(cmd, check=True)
    if rotate is not None:
        # Like a phone held upright: landscape pixels plus a rotation tag.
        tagged = path.with_name("tagged-" + path.name)
        subprocess.run(
            [tools.ffmpeg(), "-v", "error", "-y", "-display_rotation:v:0", str(rotate), "-i", str(path), "-c", "copy", str(tagged)],
            check=True,
        )
        tagged.replace(path)
    return path


def make_tone(path: Path, seconds: float, tone: int = 880) -> Path:
    subprocess.run(
        [tools.ffmpeg(), "-v", "error", "-y", "-f", "lavfi", "-i", f"sine=frequency={tone}:duration={seconds}", str(path)],
        check=True,
    )
    return path


@pytest.fixture
def media(tmp_path):
    return {
        "landscape": make_clip(tmp_path / "landscape.mp4", 3),
        "silent": make_clip(tmp_path / "silent.mp4", 2, audio=False),
        "portrait": make_clip(tmp_path / "portrait.mp4", 2, size="360x640"),
        "song": make_tone(tmp_path / "song.wav", 1.5),
        "dir": tmp_path,
    }
