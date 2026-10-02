"""Provision shared proxy credentials without printing them or replacing other settings."""

import copy
import getpass
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
import tomllib
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit, urlunsplit
from urllib.request import Request, urlopen


def paths():
  return Path.home() / ".claude/settings.json", Path.home() / ".codex/config.toml"


def read(path):
  return path.read_text() if path.exists() else ""


def validate_credentials(base_url, token, source):
  if not token or not base_url:
    raise ValueError(f"{source} needs token (concealed client key) and base_url fields.")
  parsed = urlsplit(base_url)
  if (parsed.scheme not in ("http", "https") or not parsed.hostname or parsed.username
      or parsed.password or parsed.query or parsed.fragment):
    raise ValueError("The proxy base_url must be an HTTP(S) URL without credentials, query, or fragment.")
  if any(character in token for character in "\r\n"):
    raise ValueError("The proxy token must be a single line.")
  base_url = base_url.rstrip("/")
  if base_url.endswith("/v1"):
    base_url = base_url[:-3]
  return base_url, token


def search_domain_host(host):
  """Return the search-domain FQDN the system resolver picks for a bare host, else None.
  Codex's static musl build walks resolv.conf search domains itself, so a bare `mercury` can
  land on `mercury.localdomain` (LAN) instead of the Tailscale host every other client reaches."""
  if not host or "." in host or ":" in host:
    return None
  try:
    canonical = socket.getaddrinfo(host, None, flags=socket.AI_CANONNAME)[0][3].rstrip(".").lower()
  except OSError:
    return None
  return canonical if canonical.startswith(host + ".") else None


def qualify_base_url(base_url):
  parts = urlsplit(base_url)
  fqdn = search_domain_host(parts.hostname)
  if not fqdn:
    return base_url
  print(f"  ℹ Using {fqdn} for '{parts.hostname}' so Codex resolves the same host.")
  return urlunsplit(parts._replace(netloc=fqdn + (f":{parts.port}" if parts.port else "")))


def prompt_credentials():
  """Ask for the proxy settings directly (no 1Password, no GUI); token input is hidden on a TTY."""
  print("  ℹ Manual mode: enter the CLIProxyAPI settings (from the 'CLI Proxy API' 1Password item).")
  if sys.stdin.isatty():
    base_url = input("    base_url (e.g. http://mercury:8317): ")
    token = getpass.getpass("    token (hidden): ")
  else:
    base_url = sys.stdin.readline().rstrip("\r\n")
    token = sys.stdin.readline().rstrip("\r\n")
  return validate_credentials(base_url.strip(), token.strip(), "Manual input")


def op_credentials():
  account = os.environ.get("TAILOR_OP_ACCOUNT", "chamberofsecrets.1password.com")
  item_name = os.environ.get("TAILOR_AI_PROXY_ITEM", "CLI Proxy API")
  timeout = float(os.environ.get("TAILOR_OP_TIMEOUT", "20"))
  try:
    result = subprocess.run(
      ["op", "item", "get", item_name, "--account", account, "--format", "json"],
      capture_output=True, text=True, check=False, timeout=timeout,
    )
  except subprocess.TimeoutExpired:
    raise ValueError(f"1Password CLI did not answer within {timeout:g}s; it is probably waiting for "
                     "you to unlock the 1Password app (locked by the screen lock).") from None
  except FileNotFoundError:
    raise ValueError("1Password CLI (op) is not installed.") from None
  if result.returncode:
    raise ValueError(f"Cannot read 1Password item '{item_name}'; unlock 1Password and retry.")
  item = json.loads(result.stdout)
  fields = {field.get("label", "").lower(): field.get("value") for field in item.get("fields", [])}
  return validate_credentials(fields.get("base_url", ""), fields.get("token", ""),
                              f"1Password item '{item_name}'")


def proxy_credentials(manual=False):
  """Resolve base_url + token: env vars, then --manual, then 1Password with an interactive fallback."""
  env_url = os.environ.get("TAILOR_AI_PROXY_BASE_URL", "")
  env_token = os.environ.get("TAILOR_AI_PROXY_TOKEN", "")
  if env_url or env_token:
    print("  ℹ Using TAILOR_AI_PROXY_BASE_URL / TAILOR_AI_PROXY_TOKEN from the environment.")
    return validate_credentials(env_url, env_token, "TAILOR_AI_PROXY_* environment")
  if manual:
    return prompt_credentials()
  try:
    return op_credentials()
  except ValueError as error:
    if not sys.stdin.isatty():
      raise ValueError(f"{error}\n    Without a UI: rerun with --manual, or set "
                       "TAILOR_AI_PROXY_BASE_URL and TAILOR_AI_PROXY_TOKEN.") from None
    print(f"  ⚠ {error}")
    return prompt_credentials()


def patch_table(text, table, changes):
  """Edit ordinary TOML tables; a semantic comparison below guards unusual syntax."""
  headers = list(re.finditer(r"(?m)^[ \t]*\[([^\n]+)\][ \t]*(?:#[^\n]*)?$", text))
  start, end = 0, headers[0].start() if headers else len(text)
  if table:
    for index, header in enumerate(headers):
      try:
        document = tomllib.loads(header.group() + "\n__tailor_table__ = true\n")
        for part in table:
          document = document[part]
        matched = document.get("__tailor_table__") is True
      except (ValueError, KeyError, TypeError, AttributeError):
        matched = False
      if matched:
        start = header.end() + (1 if text[header.end():].startswith("\n") else 0)
        end = headers[index + 1].start() if index + 1 < len(headers) else len(text)
        break
    else:
      text = text.rstrip() + "\n\n[" + ".".join(table) + "]\n"
      start = end = len(text)
  body = text[start:end]
  for key, value in changes.items():
    assignment = f"{key} = {json.dumps(value, ensure_ascii=False)}\n"
    pattern = rf"(?m)^[ \t]*(?:{re.escape(key)}|\"{re.escape(key)}\"|'{re.escape(key)}')[ \t]*=[^\n]*(?:\n|$)"
    if re.search(pattern, body):
      body = re.sub(pattern, lambda match: assignment, body)
    else:
      body = body.rstrip() + ("\n" if body.strip() else "") + assignment
  return text[:start] + body + text[end:]


def codex_settings(text, base_url, token):
  original = tomllib.loads(text)
  expected = copy.deepcopy(original)
  expected["model_provider"] = "cliproxyapi"
  provider = expected.setdefault("model_providers", {}).setdefault("cliproxyapi", {})
  # Conflicting custom auth mechanisms need an explicit migration, not a blind merge.
  if any(key in provider for key in ("auth", "env_key")):
    raise ValueError("Existing cliproxyapi auth/env_key configuration needs manual reconciliation.")
  managed = {
    "name": "CLIProxyAPI",
    "base_url": base_url + "/v1",
    "experimental_bearer_token": token,
    "wire_api": "responses",
    "requires_openai_auth": False,
    "supports_websockets": True,
  }
  provider.update(managed)
  if original == expected:
    return text
  updated = patch_table(text, (), {"model_provider": "cliproxyapi"})
  old_provider = original.get("model_providers", {}).get("cliproxyapi", {})
  changes = {key: value for key, value in managed.items() if old_provider.get(key) != value}
  if changes:
    updated = patch_table(updated, ("model_providers", "cliproxyapi"), changes)
  if tomllib.loads(updated) != expected:
    raise ValueError("Cannot safely merge this Codex TOML layout; config has not been changed.")
  return updated


def claude_settings(text, base_url, token):
  settings = json.loads(text or "{}")
  original = copy.deepcopy(settings)
  env = settings.setdefault("env", {})
  env.update({
    "ANTHROPIC_BASE_URL": base_url,
    "ANTHROPIC_AUTH_TOKEN": token,
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
  })
  for key, value in {
    "API_TIMEOUT_MS": "600000",
    "CLAUDE_API_TIMEOUT": "600000",
    "MCP_TIMEOUT": "30000",
    "MCP_TOOL_TIMEOUT": "600000",
  }.items():
    env.setdefault(key, value)
  return text if settings == original else json.dumps(settings, indent=2, ensure_ascii=False) + "\n"


def write_private(path, text):
  path = path.resolve()
  path.parent.mkdir(parents=True, exist_ok=True)
  if path.exists() and path.read_text() == text:
    path.chmod(0o600)
    print(f"  ✓ Already configured: {path}")
    return
  backup = path.with_name(path.name + ".bak.before-tailor-ai-proxy")
  if path.exists() and not backup.exists():
    with backup.open("xb") as output:
      os.fchmod(output.fileno(), 0o600)
      output.write(path.read_bytes())
  fd, stage = tempfile.mkstemp(prefix=".tailor-ai-proxy-", dir=path.parent)
  try:
    with os.fdopen(fd, "w") as output:
      output.write(text)
    os.replace(stage, path)
  finally:
    if os.path.exists(stage):
      os.unlink(stage)
  print(f"  ✓ Configured: {path}")


def verify(client):
  claude, codex = paths()
  if client == "claude":
    env = json.loads(read(claude) or "{}").get("env", {})
    base_url = env.get("ANTHROPIC_BASE_URL", "").rstrip("/") + "/v1"
    token = env.get("ANTHROPIC_AUTH_TOKEN")
  else:
    settings = tomllib.loads(read(codex))
    provider = settings.get("model_providers", {}).get("cliproxyapi", {})
    if settings.get("model_provider") != "cliproxyapi":
      raise ValueError("Codex is not using CLIProxyAPI; run ./tailor.sh ai-proxy.")
    base_url = provider.get("base_url", "")
    token = provider.get("experimental_bearer_token")
  if not token or not base_url.startswith(("http://", "https://")):
    raise ValueError(f"{client} proxy settings are missing; run ./tailor.sh ai-proxy.")
  if client == "codex" and (fqdn := search_domain_host(urlsplit(base_url).hostname)):
    raise ValueError(f"Codex may resolve the bare proxy host differently than {fqdn}; run ./tailor.sh ai-proxy.")
  request = Request(base_url.rstrip("/") + "/models", headers={"Authorization": "Bearer " + token})
  try:
    with urlopen(request, timeout=15) as response:
      models = json.load(response)
    if not isinstance(models.get("data"), list) or not models["data"]:
      raise ValueError("The proxy returned no models.")
  except HTTPError as error:
    raise ValueError(f"{client} proxy rejected the request (HTTP {error.code}); check the client token.") from None
  except (URLError, TimeoutError):
    raise ValueError(f"{client} proxy is unreachable; check Tailscale and Mercury.") from None
  print(f"  ✓ {client} proxy authentication and model discovery verified")


def main():
  if sys.argv[1:] in (["setup"], ["setup", "--manual"]):
    base_url, token = proxy_credentials(manual=len(sys.argv) == 3)
    base_url = qualify_base_url(base_url)
    claude, codex = paths()
    # Parse and validate both candidates before touching either live file.
    claude_text = claude_settings(read(claude), base_url, token)
    codex_text = codex_settings(read(codex), base_url, token)
    write_private(claude, claude_text)
    write_private(codex, codex_text)
  elif len(sys.argv) == 3 and sys.argv[1] == "verify" and sys.argv[2] in ("claude", "codex"):
    verify(sys.argv[2])
  else:
    raise ValueError("Usage: ai-proxy.py setup [--manual] | verify claude | verify codex")


if __name__ == "__main__":
  os.umask(0o077)
  try:
    main()
  except (json.JSONDecodeError, tomllib.TOMLDecodeError):
    sys.exit("  ✗ Invalid JSON/TOML; existing configuration was not replaced.")
  except (ValueError, OSError) as error:
    sys.exit(f"  ✗ {error}")
