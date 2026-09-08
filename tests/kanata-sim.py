#!/usr/bin/env python3
"""Exercise typing and modifier chords with Kanata 1.12's simulator."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
SIMULATOR = os.environ.get("KANATA_SIM_BIN", "kanata_simulated_input")


class LayoutTest(unittest.TestCase):
    def setUp(self):
        if not shutil.which(SIMULATOR):
            self.fail("Set KANATA_SIM_BIN to Kanata 1.12's kanata_simulated_input binary")
        self.temp = tempfile.TemporaryDirectory(prefix="kanata-sim-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copy(REPO / "kanata/homerow-mods.kbd", self.root)
        (self.root / "devices.kbd").write_text(
            "(defcfg process-unmapped-keys yes concurrent-tap-hold yes)\n"
        )

    def simulate(self, sequence):
        simulation = self.root / "input.sim"
        simulation.write_text(sequence)
        result = subprocess.run(
            [SIMULATOR, "-c", str(self.root / "homerow-mods.kbd"), "-s", str(simulation)],
            capture_output=True, text=True, check=True,
        )
        return re.findall(r"^out:([↓↑].+)$", result.stdout, re.MULTILINE)

    def test_each_modifier(self):
        for key, mod, letter in (
            ("a", "LCtrl", "u"), ("s", "LAlt", "u"),
            ("d", "LGui", "u"), ("f", "LShift", "u"),
            ("j", "RShift", "w"), ("k", "RGui", "w"),
            ("l", "RAlt", "w"), (";", "RCtrl", "w"),
        ):
            with self.subTest(key=key):
                self.assertEqual(self.simulate(
                    f"t:300 d:{key} t:180 d:{letter} t:30 u:{letter} t:20 u:{key} t:300"
                ), [f"↓{mod}", f"↓{letter.upper()}", f"↑{letter.upper()}", f"↑{mod}"])

    def test_stacked_modifiers(self):
        for keys, mods, letter in (
            (["d", "f"], ["LGui", "LShift"], "u"),
            (["a", "s", "d", "f"], ["LCtrl", "LAlt", "LGui", "LShift"], "u"),
            ([";", "l", "k", "j"], ["RCtrl", "RAlt", "RGui", "RShift"], "w"),
        ):
            with self.subTest(keys=keys):
                presses = " ".join(f"d:{key} t:20" for key in keys)
                releases = " ".join(f"u:{key} t:20" for key in reversed(keys))
                self.assertEqual(self.simulate(
                    f"t:300 {presses} t:180 d:{letter} t:30 u:{letter} t:20 {releases} t:300"
                ), [*("↓" + mod for mod in mods), f"↓{letter.upper()}", f"↑{letter.upper()}",
                    *("↑" + mod for mod in reversed(mods))])

    def test_rapid_typing_stays_letters(self):
        keys = ["e", "a", "s", "d", "f", "j", "k", "l"]
        sequence = " ".join(f"d:{key} t:20 u:{key} t:20" for key in keys)
        self.assertEqual(self.simulate(f"t:300 {sequence} t:300"),
                         [event + key.upper() for key in keys for event in ("↓", "↑")])

    def test_quick_chord_does_not_need_full_hold_timeout(self):
        self.assertEqual(self.simulate(
            "t:300 d:d t:20 d:f t:20 d:u t:30 u:u t:20 u:f t:20 u:d t:300"
        ), ["↓LGui", "↓LShift", "↓U", "↑U", "↑LShift", "↑LGui"])

    def test_typing_guard_prevents_nested_accidental_shift(self):
        # F stays down while U is tapped; the recent E makes F a letter.
        self.assertEqual(self.simulate(
            "t:300 d:e t:20 u:e t:20 d:f t:20 d:u t:20 u:u t:20 u:f t:300"
        ), ["↓E", "↑E", "↓F", "↓U", "↑U", "↑F"])

    def test_tap_repress_keeps_letter_held(self):
        self.assertEqual(self.simulate(
            "t:300 d:f t:30 u:f t:30 d:f t:300 u:f t:300"
        ), ["↓F", "↑F", "↓F", "↑F"])

    def test_left_alt_is_a_normal_modifier(self):
        self.assertEqual(self.simulate(
            "t:300 d:lalt t:20 d:tab t:20 u:tab t:20 u:lalt t:300"
        ), ["↓LAlt", "↓Tab", "↑Tab", "↑LAlt"])


if __name__ == "__main__":
    unittest.main()
