import json

import pytest

from videomerger import cli


def run(capsys, *argv):
    code = cli.main(list(argv))
    out, err = capsys.readouterr()
    return code, out, err


def test_missing_recipe_is_a_recipe_error_not_a_crash(capsys, tmp_path):
    code, out, err = run(capsys, "run", str(tmp_path / "nope.json"))
    assert code == 2
    assert out == ""
    assert "Recipe error: Recipe file not found" in err


@pytest.mark.parametrize(
    "content, message",
    [
        ("{ not json", "not valid JSON"),
        ('{"clips": [{"path": "a.mp4", "rotate": 45}]}', "rotate"),
        (None, "not found"),
    ],
)
def test_json_mode_reports_recipe_errors_on_stdout(capsys, tmp_path, content, message):
    path = tmp_path / "recipe.json"
    if content is not None:
        path.write_text(content, encoding="utf-8")
    code, out, err = run(capsys, "run", str(path), "--json")
    assert code == 2
    result = json.loads(out)
    assert result["ok"] is False and message in result["error"]


def test_json_mode_reports_bad_merge_settings_on_stdout(capsys):
    code, out, err = run(capsys, "merge", "a.mp4", "--fps", "0", "--json")
    assert code == 2
    assert json.loads(out) == {"ok": False, "error": "Recipe error: recipe.fps: use 1 to 120"}


def test_without_json_errors_stay_on_stderr(capsys):
    code, out, err = run(capsys, "merge", "a.mp4", "--fps", "0")
    assert code == 2
    assert out == ""
    assert "recipe.fps" in err


def test_output_onto_an_input_is_refused(capsys, media):
    clip = media["landscape"]
    before = clip.read_bytes()
    code, out, err = run(capsys, "merge", str(clip), "-o", str(clip), "--json")
    assert code == 1
    assert "also one of the inputs" in json.loads(out)["error"]
    assert clip.read_bytes() == before
