import json

import pytest
from conftest import make_clip

from videomerger import engine
from videomerger import ffmpeg as tools
from videomerger.recipe import RecipeError, from_dict, load


def export(media, **recipe):
    recipe.setdefault("output", "out.mp4")
    return engine.run(from_dict(recipe, media["dir"]))


def test_merges_clips_with_and_without_sound(media):
    result = export(media, clips=["landscape.mp4", "silent.mp4"])
    info = tools.probe(result.output)
    assert (info.width, info.height) == (1280, 720)
    assert info.has_audio
    assert info.duration == pytest.approx(5, abs=0.15)


def test_trim_and_rotate(media):
    result = export(media, clips=[{"path": "landscape.mp4", "start": 0.5, "end": "0:02", "rotate": 90}], resolution="480p")
    info = tools.probe(result.output)
    assert (info.width, info.height) == (480, 852)  # turned to portrait; 853.3 rounds down to even
    assert info.duration == pytest.approx(1.5, abs=0.15)


def test_first_clip_sets_shape(media):
    result = export(media, clips=["portrait.mp4", "landscape.mp4"], resolution="original")
    info = tools.probe(result.output)
    assert (info.width, info.height) == (360, 640)


def test_phone_rotation_tag_is_respected(media):
    make_clip(media["dir"] / "phone.mp4", 1, rotate=90)
    result = export(media, clips=["phone.mp4", "landscape.mp4"])
    info = tools.probe(result.output)
    assert (info.width, info.height) == (720, 1280)


def test_sound_from_another_file_loops_and_stops_with_the_video(media):
    result = export(media, clips=["landscape.mp4", "silent.mp4"], mute_clips=True, sound={"path": "song.wav", "loop": True})
    info = tools.probe(result.output)
    assert info.has_audio
    assert info.duration == pytest.approx(5, abs=0.15)


def test_sound_mixed_with_clip_sound(media):
    result = export(media, clips=["landscape.mp4"], sound={"path": "song.wav", "loop": False, "volume": 0.5})
    assert tools.probe(result.output).duration == pytest.approx(3, abs=0.15)


def test_no_sound_at_all(media):
    result = export(media, clips=["landscape.mp4"], mute_clips=True)
    assert not tools.probe(result.output).has_audio


def test_subtitles_from_file_are_burned_and_saved(media):
    srt = media["dir"] / "caps.srt"
    srt.write_text("1\n00:00:00,000 --> 00:00:02,000\nHello there\n", encoding="utf-8")
    result = export(media, clips=["landscape.mp4"], subtitles={"mode": "file", "file": "caps.srt"})
    assert result.srt and open(result.srt, encoding="utf-8").read().strip().endswith("Hello there")
    assert tools.probe(result.output).duration == pytest.approx(3, abs=0.15)


def test_recipe_file_paths_are_relative_to_the_recipe(media):
    path = media["dir"] / "recipe.json"
    path.write_text(json.dumps({"clips": ["landscape.mp4"], "output": "sub/final.mp4", "resolution": "480p"}))
    result = engine.run(load(path))
    assert result.output == str(media["dir"] / "sub" / "final.mp4")


def test_cancel(media):
    job = engine.Job(from_dict({"clips": ["landscape.mp4"]}, media["dir"]))
    job.cancel()
    with pytest.raises(engine.Cancelled):
        job.run()


def test_clear_errors(media):
    with pytest.raises(engine.ExportError, match="has no video"):
        export(media, clips=["song.wav"])
    with pytest.raises(engine.ExportError, match="past the end"):
        export(media, clips=[{"path": "landscape.mp4", "start": 10}])
    with pytest.raises(engine.ExportError, match="not found"):
        export(media, clips=["missing.mp4"])


@pytest.mark.parametrize(
    "recipe, message",
    [
        ({}, "at least one clip"),
        ({"clips": [{"path": "a.mp4", "rotate": 45}]}, "rotate"),
        ({"clips": [{"path": "a.mp4", "start": 5, "end": 2}]}, "after start"),
        ({"clips": ["a.mp4"], "resolution": "4k"}, "resolution"),
        ({"clips": ["a.mp4"], "subtitles": {"mode": "file"}}, "needs"),
        ({"clips": ["a.mp4"], "colour": "red"}, "unknown"),
        ({"clips": [{"path": "a.mp4", "start": "1:xx"}]}, "not a time"),
    ],
)
def test_recipe_validation(recipe, message):
    with pytest.raises(RecipeError, match=message):
        from_dict(recipe)


def test_output_size():
    assert engine.output_size(1920, 1080, 720) == (1280, 720)
    assert engine.output_size(1080, 1920, 720) == (720, 1280)
    assert engine.output_size(1440, 1080, 480) == (640, 480)
    assert engine.output_size(1279, 721, None) == (1278, 720)
