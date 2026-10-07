"""Regression checks for safe, repeatable Claude/Codex proxy provisioning."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import tomllib
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

REPO = Path(__file__).resolve().parents[1]
TOKEN = 'test-client-token-"quoted"-\\literal'


class ProxyTest(unittest.TestCase):
  def setUp(self):
    self.temp = tempfile.TemporaryDirectory()
    self.addCleanup(self.temp.cleanup)
    self.root = Path(self.temp.name)
    self.home = self.root / "home"
    self.home.mkdir()
    self.bin = self.root / "bin"
    self.bin.mkdir()
    op = self.bin / "op"
    op.write_text('#!/bin/bash\ncat "$PROXY_TEST_ITEM"\n')
    op.chmod(0o755)
    self.item = self.root / "item.json"
    self.set_item()
    self.env = dict(os.environ, HOME=str(self.home),
                    PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                    PROXY_TEST_ITEM=str(self.item))
    self.claude = self.home / ".claude/settings.json"
    self.codex = self.home / ".codex/config.toml"

  def set_item(self, token=TOKEN, url="http://mercury:8317"):
    self.item.write_text(json.dumps({"fields": [
      {"label": "password", "value": "management-password-must-not-be-used"},
      {"label": "token", "value": token},
      {"label": "base_url", "value": url},
    ]}))

  def run_setup(self, success=True):
    result = subprocess.run([str(REPO / "tailor.sh"), "ai-proxy"], env=self.env,
                            capture_output=True, text=True)
    self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
    self.assertNotIn(TOKEN, result.stdout + result.stderr)
    self.assertNotIn("management-password-must-not-be-used", result.stdout + result.stderr)
    return result

  def write_existing(self):
    self.claude.parent.mkdir()
    self.codex.parent.mkdir()
    self.claude.write_text(json.dumps({"model": "fable[1m]", "hooks": {"Stop": []},
      "enabledPlugins": {"example": True}, "env": {"KEEP": "yes", "MCP_TIMEOUT": "12345"}}))
    self.codex.write_text('''# Keep the user's comments and unrelated settings.
model = "gpt-example"
model_provider = "openai"
model_reasoning_effort = "high"

[projects."/work/project"]
trust_level = "trusted"

[features]
hooks = true
api_key_model_discovery = false
''')
    (self.claude.parent / ".credentials.json").write_text('{"oauth": "unchanged"}')
    (self.codex.parent / "auth.json").write_text('{"oauth": "unchanged"}')

  def test_fresh_install_and_second_run(self):
    self.run_setup()
    claude = json.loads(self.claude.read_text())
    codex = tomllib.loads(self.codex.read_text())
    self.assertEqual(claude["env"]["ANTHROPIC_AUTH_TOKEN"], TOKEN)
    self.assertEqual(claude["env"]["ANTHROPIC_BASE_URL"], "http://mercury:8317")
    self.assertEqual(codex["model_provider"], "cliproxyapi")
    self.assertTrue(codex["features"]["api_key_model_discovery"])
    provider = codex["model_providers"]["cliproxyapi"]
    self.assertEqual(provider["experimental_bearer_token"], TOKEN)
    self.assertEqual(provider["base_url"], "http://mercury:8317/v1")
    self.assertEqual(provider["model_catalog_url"], "http://mercury:8317/v1/models")
    self.assertFalse(provider["requires_openai_auth"])
    before = [(p.read_bytes(), p.stat().st_mtime_ns) for p in (self.claude, self.codex)]
    self.run_setup()
    self.assertEqual(before, [(p.read_bytes(), p.stat().st_mtime_ns) for p in (self.claude, self.codex)])
    for path in (self.claude, self.codex):
      self.assertEqual(path.stat().st_mode & 0o777, 0o600)
      self.assertFalse(path.with_name(path.name + ".bak.before-tailor-ai-proxy").exists())

  def test_preserves_settings_credentials_and_original_backups_on_rotation(self):
    self.write_existing()
    old = {p: p.read_bytes() for p in (self.claude, self.codex)}
    self.run_setup()
    settings = json.loads(self.claude.read_text())
    self.assertEqual(settings["model"], "fable[1m]")
    self.assertEqual(settings["hooks"], {"Stop": []})
    self.assertEqual(settings["enabledPlugins"], {"example": True})
    self.assertEqual(settings["env"]["KEEP"], "yes")
    self.assertEqual(settings["env"]["MCP_TIMEOUT"], "12345")
    codex = tomllib.loads(self.codex.read_text())
    self.assertEqual(codex["projects"], {"/work/project": {"trust_level": "trusted"}})
    self.assertEqual(codex["model"], "gpt-example")
    self.assertEqual(codex["model_reasoning_effort"], "high")
    self.assertTrue(codex["features"]["hooks"])
    self.assertTrue(codex["features"]["api_key_model_discovery"])
    self.assertTrue(self.codex.read_text().startswith("# Keep the user's comments"))
    self.set_item(token="rotated-client-token", url="http://new-proxy:8317/v1/")
    self.run_setup()
    self.assertEqual(json.loads(self.claude.read_text())["env"]["ANTHROPIC_BASE_URL"], "http://new-proxy:8317")
    provider = tomllib.loads(self.codex.read_text())["model_providers"]["cliproxyapi"]
    self.assertEqual(provider["experimental_bearer_token"], "rotated-client-token")
    self.assertEqual(provider["model_catalog_url"], "http://new-proxy:8317/v1/models")
    for path in old:
      backup = path.with_name(path.name + ".bak.before-tailor-ai-proxy")
      self.assertEqual(backup.read_bytes(), old[path])
      self.assertEqual(backup.stat().st_mode & 0o777, 0o600)
    self.assertEqual((self.claude.parent / ".credentials.json").read_text(), '{"oauth": "unchanged"}')
    self.assertEqual((self.codex.parent / "auth.json").read_text(), '{"oauth": "unchanged"}')

  def test_existing_provider_is_repaired_without_duplicate_tables(self):
    self.write_existing()
    with self.codex.open("a") as config:
      config.write('''
[model_providers."cliproxyapi"]
name = "CLIProxyAPI"
base_url = "http://old-proxy/v1"
model_catalog_url = "http://old-proxy/v1/models"
experimental_bearer_token = "old-token"
requires_openai_auth = true
request_max_retries = 9
''')
    self.run_setup()
    provider = tomllib.loads(self.codex.read_text())["model_providers"]["cliproxyapi"]
    self.assertEqual(provider["request_max_retries"], 9)
    self.assertFalse(provider["requires_openai_auth"])
    self.assertEqual(provider["experimental_bearer_token"], TOKEN)
    self.assertEqual(provider["model_catalog_url"], "http://mercury:8317/v1/models")

  def test_bad_config_leaves_both_files_untouched(self):
    self.write_existing()
    for malformed in ('model = "unterminated', 'model_providers = { cliproxyapi = { name = "inline" } }\n',
                      '[model_providers.cliproxyapi]\nenv_key = "CUSTOM_TOKEN"\n'):
      with self.subTest(malformed=malformed):
        self.codex.write_text(malformed)
        before = [p.read_bytes() for p in (self.claude, self.codex)]
        self.run_setup(success=False)
        self.assertEqual(before, [p.read_bytes() for p in (self.claude, self.codex)])
    self.codex.write_text('model = "okay"\n')
    self.claude.write_text('{"broken"')
    before = [p.read_bytes() for p in (self.claude, self.codex)]
    self.run_setup(success=False)
    self.assertEqual(before, [p.read_bytes() for p in (self.claude, self.codex)])

  def test_missing_client_key_never_uses_management_password(self):
    self.set_item(token="")
    self.run_setup(success=False)
    self.assertFalse(self.claude.exists())
    self.assertFalse(self.codex.exists())

  def test_manual_mode_env_vars_bypass_1password(self):
    self.item.unlink()  # op would fail; the env vars must win before it is consulted
    env = dict(self.env, TAILOR_AI_PROXY_BASE_URL="http://mercury:8317/v1/", TAILOR_AI_PROXY_TOKEN=TOKEN)
    result = subprocess.run([str(REPO / "setup-ai-proxy.sh")], env=env, capture_output=True, text=True)
    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
    self.assertNotIn(TOKEN, result.stdout + result.stderr)
    settings = json.loads(self.claude.read_text())
    self.assertEqual(settings["env"]["ANTHROPIC_BASE_URL"], "http://mercury:8317")
    self.assertEqual(settings["env"]["ANTHROPIC_AUTH_TOKEN"], TOKEN)
    codex = tomllib.loads(self.codex.read_text())
    self.assertEqual(codex["model_providers"]["cliproxyapi"]["experimental_bearer_token"], TOKEN)

  def test_manual_flag_prompts_for_values(self):
    self.item.unlink()
    result = subprocess.run([str(REPO / "setup-ai-proxy.sh"), "--manual"], env=self.env,
                            input=f"http://mercury:8317\n{TOKEN}\n", capture_output=True, text=True)
    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
    self.assertIn("Manual mode", result.stdout)
    self.assertNotIn(TOKEN, result.stdout + result.stderr)
    self.assertEqual(json.loads(self.claude.read_text())["env"]["ANTHROPIC_AUTH_TOKEN"], TOKEN)
    result = subprocess.run([str(REPO / "setup-ai-proxy.sh"), "--manual"], env=self.env,
                            input="ftp://nope\n\n", capture_output=True, text=True)
    self.assertNotEqual(result.returncode, 0)

  def test_locked_1password_fails_fast_without_tty(self):
    (self.bin / "op").write_text("#!/bin/bash\nsleep 30\n")
    env = dict(self.env, TAILOR_OP_TIMEOUT="1")
    result = subprocess.run([str(REPO / "tailor.sh"), "ai-proxy"], env=env, stdin=subprocess.DEVNULL,
                            capture_output=True, text=True, timeout=15)
    self.assertNotEqual(result.returncode, 0)
    self.assertIn("did not answer within 1s", result.stdout + result.stderr)
    self.assertIn("--manual", result.stdout + result.stderr)
    self.assertFalse(self.claude.exists())

  def test_proxy_auth_verification_without_oauth(self):
    class Handler(BaseHTTPRequestHandler):
      def do_GET(handler):
        valid = handler.path == "/v1/models" and handler.headers.get("Authorization") == "Bearer " + TOKEN
        handler.send_response(200 if valid else 401)
        handler.end_headers()
        handler.wfile.write(b'{"data":[{"id":"example-model"}]}')

      def log_message(handler, *_):
        pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    self.addCleanup(server.server_close)
    self.addCleanup(server.shutdown)
    self.set_item(url=f"http://127.0.0.1:{server.server_port}")
    self.run_setup()
    for client in ("claude", "codex"):
      result = subprocess.run(["python3", str(REPO / "lib/ai-proxy.py"), "verify", client],
                              env=self.env, capture_output=True, text=True)
      self.assertEqual(result.returncode, 0, result.stderr)
    self.set_item(token="wrong-client-token", url=f"http://127.0.0.1:{server.server_port}")
    self.run_setup()
    result = subprocess.run(["python3", str(REPO / "lib/ai-proxy.py"), "verify", "codex"],
                            env=self.env, capture_output=True, text=True)
    self.assertNotEqual(result.returncode, 0)
    self.assertIn("HTTP 401", result.stderr)
    self.assertNotIn("wrong-client-token", result.stderr)


if __name__ == "__main__":
  unittest.main()
