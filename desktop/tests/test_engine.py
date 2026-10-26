import json

import pytest
from conftest import make_clip, make_tone

from videomerger import engine
from videomerger import ffmpeg as tools
from videomerger.recipe import RecipeError, from_dict, load


def export(media, **recipe):
    recipe.setdefault("output", "out.mp4")
    return engine.run(from_dict(recipe, media["dir"]))


def test_merges_clips_with_and_without_sound(media):
    result = export(media, clips=["landscape.mp4", "silent.mp4"])
    info = tools.probe(result.output)
    assert (info.width, info.height) == (1920, 1080)
    assert info.has_audio
    assert info.duration == pytest.approx(5, abs=0.15)


def test_trim_and_rotate(media):
    result = export(media, clips=[{"path": "landscape.mp4", "start": 0.5, "end": "0:02", "rotate": 90}], resolution="2k")
    info = tools.probe(result.output)
    assert (info.width, info.height) == (1440, 2560)  # turned to portrait, scaled up to 2K
    assert info.duration == pytest.approx(1.5, abs=0.15)


def test_first_clip_sets_shape(media):
    result = export(media, clips=["portrait.mp4", "landscape.mp4"], resolution="1080p")
    info = tools.probe(result.output)
    assert (info.width, info.height) == (1080, 1920)


def test_phone_rotation_tag_is_respected(media):
    make_clip(media["dir"] / "phone.mp4", 1, rotate=90)
    result = export(media, clips=["phone.mp4", "landscape.mp4"])
    info = tools.probe(result.output)
    assert (info.width, info.height) == (1080, 1920)


def test_sound_from_another_file_loops_and_stops_with_the_video(media):
    result = export(media, clips=["landscape.mp4", "silent.mp4"], mute_clips=True, sound={"path": "song.wav", "loop": True})
    info = tools.probe(result.output)
    assert info.has_audio
    assert info.duration == pytest.approx(5, abs=0.15)


def test_sound_mixed_with_clip_sound(media):
    result = export(media, clips=["landscape.mp4"], sound={"path": "song.wav", "loop": False, "volume": 0.5})
    assert tools.probe(result.output).duration == pytest.approx(3, abs=0.15)


def test_video_repeats_until_a_longer_sound_ends(media):
    make_tone(media["dir"] / "long.wav", 12)
    result = export(media, clips=["landscape.mp4", "silent.mp4"], mute_clips=True, sound={"path": "long.wav", "repeat_video": True})
    info = tools.probe(result.output)
    assert info.has_audio
    assert info.duration == pytest.approx(12, abs=0.15)  # 5 s of clips: twice, then 2 s of the first clip


def test_repeated_video_keeps_the_clips_sound_mixed_in(media):
    make_tone(media["dir"] / "long.wav", 7)
    result = export(media, clips=["portrait.mp4"], sound={"path": "long.wav", "start": 1, "repeat_video": True})
    assert tools.probe(result.output).duration == pytest.approx(6, abs=0.15)  # the sound from 0:01 lasts 6 s


def test_repeat_video_does_nothing_when_the_sound_is_shorter(media):
    result = export(media, clips=["landscape.mp4", "silent.mp4"], sound={"path": "song.wav", "repeat_video": True})
    assert tools.probe(result.output).duration == pytest.approx(5, abs=0.15)


def test_repeat_to():
    info = tools.MediaInfo(duration=3, width=640, height=360, has_video=True, has_audio=True)
    a, b = engine.Segment("a.mp4", 0, 3, 0, info), engine.Segment("b.mp4", 1, 2, 0, info)
    assert [(s.path, s.duration) for s in engine.repeat_to([a, b], 12)] == [("a.mp4", 3), ("b.mp4", 2), ("a.mp4", 3), ("b.mp4", 2), ("a.mp4", 2)]
    assert engine.repeat_to([a, b], 4) == [a, b]
    assert [s.start for s in engine.repeat_to([b], 5)] == [1, 1, 1]  # trims are kept on every repeat
    with pytest.raises(engine.ExportError, match="too long to repeat"):
        engine.repeat_to([a], 3 * engine.MAX_REPEATED_CLIPS + 10)


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
    path.write_text(json.dumps({"clips": ["landscape.mp4"], "output": "sub/final.mp4", "resolution": "1440p"}))
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


def test_output_never_overwrites_an_input(media):
    before = media["landscape"].read_bytes(), media["portrait"].read_bytes()
    with pytest.raises(engine.ExportError, match="also one of the inputs"):
        export(media, clips=["landscape.mp4"], output="landscape.mp4")
    with pytest.raises(engine.ExportError, match="also one of the inputs"):
        export(media, clips=["landscape.mp4"], output="portrait.mp4", sound="portrait.mp4")
    assert (media["landscape"].read_bytes(), media["portrait"].read_bytes()) == before


def test_overwrites_input_is_known_before_exporting(media):
    """The window asks this before its "Replace?" question, so it never offers to replace a clip."""

    def recipe(**data):
        return from_dict({"clips": ["landscape.mp4"], **data}, media["dir"])

    assert engine.overwrites_input(recipe(output="landscape.mp4"))
    assert engine.overwrites_input(recipe(output="landscape"))  # becomes landscape.mp4
    assert engine.overwrites_input(recipe(output="portrait.mp4", sound="portrait.mp4"))
    assert not engine.overwrites_input(recipe(output="new.mp4"))
    assert not engine.overwrites_input(recipe(output="silent.mp4"))  # exists, but not an input: "Replace?" is right
    assert engine.output_path(recipe(output="x.mov")) == media["dir"] / "x.mp4"


@pytest.mark.parametrize(
    "recipe, message",
    [
        ({}, "at least one clip"),
        ({"clips": [{"path": "a.mp4", "rotate": 45}]}, "rotate"),
        ({"clips": [{"path": "a.mp4", "start": 5, "end": 2}]}, "after start"),
        ({"clips": ["a.mp4"], "resolution": "4k"}, "1080p or 1440p"),
        ({"clips": ["a.mp4"], "resolution": "720p"}, "never below 1080p"),
        ({"clips": ["a.mp4"], "subtitles": {"mode": "file"}}, "needs"),
        ({"clips": ["a.mp4"], "colour": "red"}, "unknown"),
        ({"clips": [{"path": "a.mp4", "start": "1:xx"}]}, "not a time"),
    ],
)
def test_recipe_validation(recipe, message):
    with pytest.raises(RecipeError, match=message):
        from_dict(recipe)


def test_output_size():
    assert engine.output_size(1920, 1080, 1080) == (1920, 1080)
    assert engine.output_size(1280, 720, 1440) == (2560, 1440)  # 720p clip scaled up to 2K
    assert engine.output_size(1080, 1920, 1080) == (1080, 1920)
    assert engine.output_size(640, 480, 1080) == (1440, 1080)  # 4:3
    assert engine.output_size(1000, 1001, 1080) == (1080, 1080)  # rounds to even
