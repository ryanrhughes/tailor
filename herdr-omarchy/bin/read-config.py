#!/usr/bin/env python3

import json
import sys
import tomllib
from pathlib import Path


DEFAULTS = {
    "editor": "nvim",
    "ai": "opencode2",
    "diff": "hunk diff --watch",
    "hds_agent": None,
    "ratios": {
        "editor_terminal": 0.85,
        "editor_ai": 0.70,
        "ai_stack": 0.50,
    },
    "hdlm": {
        "warn_threshold": 5,
        "exclude": ["node_modules", "vendor"],
        "only": [],
    },
    "presets": {
        "review": {"layout": "hdl", "commands": ["cx", "codex"]},
        "swarm": {"layout": "hsl", "count": 6, "command": "opencode2"},
    },
}


def fail(message: str) -> None:
    print(f"herdr-omarchy: {message}", file=sys.stderr)
    raise SystemExit(1)


def expect_string(value: object, field: str, *, optional: bool = False) -> str | None:
    if optional and value is None:
        return None
    if not isinstance(value, str) or not value.strip():
        fail(f"{field} must be a non-empty string")
    return value


def expect_ratio(value: object, field: str) -> float:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        fail(f"{field} must be a number")
    value = float(value)
    if not 0 < value < 1:
        fail(f"{field} must be greater than 0 and less than 1")
    return value


def expect_patterns(value: object, field: str) -> list[str]:
    if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
        fail(f"{field} must be an array of non-empty strings")
    return value


def reject_unknown(mapping: dict, allowed: set[str], field: str) -> None:
    unknown = sorted(set(mapping) - allowed)
    if unknown:
        prefix = f"{field}." if field else ""
        fail(f"unknown config field: {prefix}{unknown[0]}")


def load(path: Path) -> dict:
    config = json.loads(json.dumps(DEFAULTS))
    if not path.exists():
        return config

    try:
        source = tomllib.loads(path.read_text())
    except (OSError, tomllib.TOMLDecodeError) as error:
        fail(f"could not read {path}: {error}")

    reject_unknown(
        source,
        {"editor", "ai", "diff", "hds_agent", "ratios", "hdlm", "presets"},
        "",
    )

    for key in ("editor", "ai", "diff"):
        if key in source:
            config[key] = expect_string(source[key], key)
    if "hds_agent" in source:
        config["hds_agent"] = expect_string(source["hds_agent"], "hds_agent")

    ratios = source.get("ratios", {})
    if not isinstance(ratios, dict):
        fail("ratios must be a table")
    reject_unknown(ratios, {"editor_terminal", "editor_ai", "ai_stack"}, "ratios")
    for key in ("editor_terminal", "editor_ai", "ai_stack"):
        if key in ratios:
            config["ratios"][key] = expect_ratio(ratios[key], f"ratios.{key}")

    hdlm = source.get("hdlm", {})
    if not isinstance(hdlm, dict):
        fail("hdlm must be a table")
    reject_unknown(hdlm, {"warn_threshold", "exclude", "only"}, "hdlm")
    if "warn_threshold" in hdlm:
        threshold = hdlm["warn_threshold"]
        if not isinstance(threshold, int) or isinstance(threshold, bool) or threshold < 0:
            fail("hdlm.warn_threshold must be a non-negative integer")
        config["hdlm"]["warn_threshold"] = threshold
    for key in ("exclude", "only"):
        if key in hdlm:
            config["hdlm"][key] = expect_patterns(hdlm[key], f"hdlm.{key}")

    presets = source.get("presets", {})
    if not isinstance(presets, dict):
        fail("presets must be a table")
    for name, preset in presets.items():
        if not isinstance(preset, dict):
            fail(f"presets.{name} must be a table")
        reject_unknown(preset, {"layout", "commands", "command", "count"}, f"presets.{name}")
        layout = expect_string(preset.get("layout"), f"presets.{name}.layout")
        if layout not in {"hdl", "hds", "hdlm", "hsl"}:
            fail(f"presets.{name}.layout must be hdl, hds, hdlm, or hsl")
        normalized = {"layout": layout}
        if "commands" in preset:
            normalized["commands"] = expect_patterns(
                preset["commands"], f"presets.{name}.commands"
            )
            limit = 1 if layout == "hds" else 2
            if layout == "hsl" or len(normalized["commands"]) > limit:
                fail(f"presets.{name}.commands is not valid for {layout}")
        if "command" in preset:
            normalized["command"] = expect_string(
                preset["command"], f"presets.{name}.command"
            )
        if "count" in preset:
            count = preset["count"]
            if not isinstance(count, int) or isinstance(count, bool) or count < 1:
                fail(f"presets.{name}.count must be a positive integer")
            normalized["count"] = count
        config["presets"][name] = normalized

    return config


def main() -> None:
    if len(sys.argv) not in (2, 3):
        fail("read-config.py expects CONFIG_PATH [PRESET]")
    config = load(Path(sys.argv[1]).expanduser())
    preset_name = sys.argv[2] if len(sys.argv) == 3 else None
    if preset_name:
        preset = config["presets"].get(preset_name)
        if preset is None:
            fail(f"unknown preset: {preset_name}")
        config["selected_preset"] = {"name": preset_name, **preset}
    else:
        config["selected_preset"] = None
    print(json.dumps(config, separators=(",", ":")))


if __name__ == "__main__":
    main()
