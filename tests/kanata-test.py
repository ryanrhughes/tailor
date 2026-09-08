#!/usr/bin/env python3
"""Regression checks for provisioning, gaming mode, and keyboard detection."""

import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
MOCK = r'''#!/usr/bin/python3
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
root = Path(os.environ["KANATA_TEST_ROOT"])
with (root / "calls").open("a") as log:
    log.write(json.dumps([name, *args]) + "\n")
state_file = root / "state"
state = state_file.read_text()
if name in ("pkexec", "sudo"):
    if args[0] == "install":
        target = Path(args[-1])
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(args[-2], target)
        target.chmod(0o644)
    else:
        sys.exit(subprocess.run(args).returncode)
elif name == "udevadm":
    if args[0] == "control" and os.environ.get("FAIL_RELOAD"):
        sys.exit(23)
elif name == "systemctl":
    action = args[1]
    if action == "is-active":
        active = state == "active" if args[-1] == "kanata.service" else True
        sys.exit(0 if active else 3)
    if action == "is-failed":
        sys.exit(0 if state == "failed" else 1)
    if action == "show":
        print(state)
    if action in ("start", "restart", "stop"):
        if os.environ.get("FAIL_SERVICE") == action:
            if action != "stop":
                state_file.write_text("failed")
            sys.exit(1)
        state_file.write_text("inactive" if action == "stop" else "active")
elif name == "kanata-status":
    sys.exit(0 if state == "active" and not os.environ.get("FAIL_HEALTH") else 1)
'''


class SetupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="kanata-setup-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        for directory in ("kanata", "udev", "lib", "bin"):
            shutil.copytree(REPO / directory, self.repo / directory)
        self.user = self.root / "user"
        self.state = self.root / "setup-state"
        self.rule = self.root / "etc/70-kanata.rules"
        self.runtime = self.root / "runtime"
        self.runtime.mkdir()
        self.service = self.user / ".config/systemd/user/kanata.service"
        source = (REPO / "setup-kanata.sh").read_text()
        source = source.replace('$HOME', '$KANATA_TEST_USER_DIR')
        source = source.replace(
            'STATE_DIR="${XDG_STATE_HOME:-$KANATA_TEST_USER_DIR/.local/state}/tailor/kanata"',
            'STATE_DIR="$KANATA_TEST_STATE_DIR"',
        )
        source = source.replace('RULE_TARGET=/etc/udev/rules.d/70-kanata.rules',
                                f'RULE_TARGET={self.rule}')
        (self.repo / "setup-kanata.sh").write_text(source)
        toggle = (REPO / "bin/kanata-gaming-toggle").read_text().replace(
            '${XDG_RUNTIME_DIR:?}', '${KANATA_TEST_RUNTIME:?}'
        )
        (self.repo / "bin/kanata-gaming-toggle").write_text(toggle)
        mock_bin = self.root / "mock-bin"
        mock_bin.mkdir()
        for name in ("kanata", "systemctl", "udevadm", "sudo", "pkexec", "notify-send"):
            path = mock_bin / name
            path.write_text(MOCK)
            path.chmod(0o755)
        health = self.repo / "bin/kanata-status"
        health.write_text(MOCK)
        health.chmod(0o755)
        (self.root / "state").write_text("inactive")
        (self.root / "calls").write_text("")
        self.env = dict(os.environ, PATH=f'{mock_bin}:{os.environ["PATH"]}',
                        KANATA_TEST_ROOT=str(self.root), KANATA_TEST_USER_DIR=str(self.user),
                        KANATA_TEST_STATE_DIR=str(self.state), KANATA_TEST_RUNTIME=str(self.runtime),
                        TAILOR_KANATA_DEVICES="NuPhy Air75 V3 Dongle")

    def run_setup(self, **extra):
        return subprocess.run(["/bin/bash", str(self.repo / "setup-kanata.sh")],
                              env=dict(self.env, **extra), capture_output=True, text=True)

    def calls(self):
        return [json.loads(line) for line in (self.root / "calls").read_text().splitlines()]

    def existing_service(self, state):
        self.service.parent.mkdir(parents=True, exist_ok=True)
        self.service.write_text("old service\n")
        (self.root / "state").write_text(state)

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_fresh_install_starts_and_second_run_is_noop(self):
        self.assert_success(self.run_setup())
        self.assertIn(["systemctl", "--user", "start", "kanata.service"], self.calls())
        (self.root / "calls").write_text("")
        self.assert_success(self.run_setup())
        self.assertFalse(any(call[0] in ("pkexec", "systemctl") for call in self.calls()))

    def test_fresh_install_defaults_to_all_keyboards(self):
        self.env.pop("TAILOR_KANATA_DEVICES")
        self.env.pop("TAILOR_KANATA_EXCLUDE", None)
        self.assert_success(self.run_setup())
        config = (self.user / ".config/kanata/devices.kbd").read_text()
        self.assertIn("linux-device-detect-mode keyboard-mice", config)
        self.assertNotIn("linux-dev-names-include", config)

    def test_auto_selection_replaces_allowlist_and_keeps_local_exclusions(self):
        self.assert_success(self.run_setup())
        self.assert_success(self.run_setup(TAILOR_KANATA_DEVICES="auto",
                                          TAILOR_KANATA_EXCLUDE="Mouse Keyboard Interface"))
        config_file = self.user / ".config/kanata/devices.kbd"
        config = config_file.read_text()
        self.assertNotIn("linux-dev-names-include", config)
        self.assertIn('"Mouse Keyboard Interface"', config)
        self.assertIn("linux-dev-names-exclude", config)
        self.env.pop("TAILOR_KANATA_DEVICES")
        self.env.pop("TAILOR_KANATA_EXCLUDE", None)
        self.assert_success(self.run_setup())
        self.assertEqual(config_file.read_text(), config)

    def test_existing_gaming_mode_stays_stopped(self):
        self.existing_service("inactive")
        self.assert_success(self.run_setup())
        actions = [call[2] for call in self.calls() if call[0] == "systemctl"]
        self.assertNotIn("start", actions)
        self.assertNotIn("restart", actions)
        self.assertEqual((self.root / "state").read_text(), "inactive")

    def test_failed_reload_is_retried_even_when_file_matches(self):
        self.assertEqual(self.run_setup(FAIL_RELOAD="1").returncode, 23)
        self.assertTrue(self.rule.exists())
        self.assertTrue((self.state / "udev-pending").exists())
        (self.root / "calls").write_text("")
        self.assert_success(self.run_setup())
        self.assertIn(["udevadm", "control", "--reload-rules"], self.calls())
        self.assertFalse((self.state / "udev-pending").exists())
        self.assertFalse((self.state / "service-pending").exists())

    def test_failed_restart_is_retried(self):
        self.existing_service("active")
        self.assertNotEqual(self.run_setup(FAIL_SERVICE="restart").returncode, 0)
        self.assertTrue((self.state / "service-pending").exists())
        self.assert_success(self.run_setup())
        self.assertEqual((self.root / "state").read_text(), "active")
        self.assertFalse((self.state / "service-pending").exists())

    def test_running_without_keyboard_does_not_complete_setup(self):
        self.assertNotEqual(self.run_setup(FAIL_HEALTH="1").returncode, 0)
        self.assertTrue((self.state / "service-pending").exists())
        self.assert_success(self.run_setup())
        self.assertFalse((self.state / "service-pending").exists())

    def test_local_device_selection_is_preserved(self):
        self.assert_success(self.run_setup())
        device_file = self.user / ".config/kanata/devices.kbd"
        custom = device_file.read_text().replace("NuPhy Air75 V3 Dongle", "Another keyboard")
        device_file.write_text(custom)
        self.env.pop("TAILOR_KANATA_DEVICES")
        (self.root / "calls").write_text("")
        self.assert_success(self.run_setup())
        self.assertEqual(device_file.read_text(), custom)
        self.assertIn(["systemctl", "--user", "restart", "kanata.service"], self.calls())

    def test_restart_loop_is_repaired(self):
        self.existing_service("activating")
        self.assert_success(self.run_setup())
        self.assertIn(["systemctl", "--user", "restart", "kanata.service"], self.calls())

    def test_start_failure_never_announces_enabled(self):
        result = subprocess.run(["/bin/bash", str(self.repo / "bin/kanata-gaming-toggle")],
                                env=dict(self.env, FAIL_SERVICE="start"), capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("Homerow mods ENABLED" in call for call in self.calls()))
        self.assertTrue(any("Could not start Kanata" in call for call in self.calls()))

    def test_health_failure_never_announces_enabled(self):
        result = subprocess.run(["/bin/bash", str(self.repo / "bin/kanata-gaming-toggle")],
                                env=dict(self.env, FAIL_HEALTH="1"), capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("Homerow mods ENABLED" in call for call in self.calls()))

    def test_stop_failure_never_announces_disabled(self):
        (self.root / "state").write_text("active")
        result = subprocess.run(["/bin/bash", str(self.repo / "bin/kanata-gaming-toggle")],
                                env=dict(self.env, FAIL_SERVICE="stop"), capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("Homerow mods DISABLED" in call for call in self.calls()))


class DeviceTest(unittest.TestCase):
    def test_media_only_interface_does_not_count_as_a_keyboard(self):
        module = runpy.run_path(str(REPO / "bin/kanata-status"))
        with tempfile.TemporaryDirectory(prefix="kanata-device-test-") as temporary:
            root = Path(temporary)
            descriptors = root / "proc/123/fd"
            descriptors.mkdir(parents=True)
            for event, name, bits in (("event7", "NuPhy", "40000000"),
                                      ("event10", "System Control", "10000")):
                device = root / "sys" / event / "device"
                (device / "capabilities").mkdir(parents=True)
                (device / "name").write_text(name)
                (device / "capabilities/key").write_text(bits)
                (descriptors / event).symlink_to("/dev/input/" + event)
            self.assertEqual(module["keyboard_names"](123, root / "proc", root / "sys"), {"NuPhy"})
            (descriptors / "event7").unlink()
            self.assertEqual(module["keyboard_names"](123, root / "proc", root / "sys"), set())


if __name__ == "__main__":
    unittest.main()
