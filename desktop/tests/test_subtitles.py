import json
import os
import shutil
import subprocess

import pytest

from videomerger import engine
from videomerger.recipe import from_dict
from videomerger.subtitles import group_words, to_srt


def test_groups_words_into_short_captions():
    words = [(0.0, 0.4, " Hello"), (0.5, 0.9, " world."), (1.0, 1.3, " Next"), (1.4, 1.6, " line"), (4.0, 4.5, " later")]
    cues = group_words(words)
    assert [c.text for c in cues] == ["Hello world.", "Next line", "later"]
    assert (cues[0].start, cues[0].end) == (0.0, 0.9)


def test_long_speech_is_split():
    words = [(i * 0.3, i * 0.3 + 0.25, "word") for i in range(30)]
    cues = group_words(words)
    assert all(len(c.text) <= 42 and c.end - c.start <= 5 for c in cues)
    assert sum(len(c.text.split()) for c in cues) == 30


def test_srt_format():
    srt = to_srt(group_words([(61.25, 62.5, "Hi")]))
    assert srt == "1\n00:01:01,250 --> 00:01:02,500\nHi\n"


def test_model_download_failure_is_a_clear_json_error(media, monkeypatch, capsys):
    import faster_whisper

    def offline(*args, **kwargs):
        raise OSError("no internet")

    monkeypatch.setattr(faster_whisper, "WhisperModel", offline)
    monkeypatch.chdir(media["dir"])
    from videomerger.cli import main

    code = main(["merge", "landscape.mp4", "-o", "subs.mp4", "--subtitles", "--json"])
    result = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert code == 1 and result["ok"] is False
    assert "you need internet" in result["error"] and "no internet" in result["error"]


@pytest.mark.skipif(not os.environ.get("RUN_WHISPER"), reason="set RUN_WHISPER=1 (downloads the Whisper tiny model; needs espeak-ng)")
def test_subtitles_from_speech(tmp_path):
    """Speaks a sentence with espeak-ng over a test video and checks Whisper hears it."""
    speech = tmp_path / "speech.wav"
    subprocess.run([shutil.which("espeak-ng"), "-w", str(speech), "Hello world. This is a video merger test."], check=True)
    from conftest import make_clip

    make_clip(tmp_path / "clip.mp4", 5, audio=False)
    recipe = from_dict(
        {
            "clips": ["clip.mp4"],
            "mute_clips": True,
            "sound": {"path": "speech.wav", "loop": False},
            "subtitles": {"mode": "speech", "model": "tiny", "language": "en"},
            "output": "out.mp4",
        },
        tmp_path,
    )
    result = engine.run(recipe)
    text = open(result.srt, encoding="utf-8").read().lower()
    assert "hello" in text and "test" in text
