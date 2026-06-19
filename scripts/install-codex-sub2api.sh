#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://771to8vw3580.vicp.fun}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

echo "Codex Sub2API installer"
echo "Base URL: $BASE_URL"
printf "Paste API key: "
IFS= read -r API_KEY
API_KEY="$(printf '%s' "$API_KEY" | tr -d '\r\n ')"

if [[ -z "$API_KEY" ]]; then
  echo "ERROR: API key is empty." >&2
  exit 2
fi

mkdir -p "$CODEX_HOME"
CONFIG_PATH="$CODEX_HOME/config.toml"
AUTH_PATH="$CODEX_HOME/auth.json"
STAMP="$(date +%Y%m%d%H%M%S)"

[[ -f "$CONFIG_PATH" ]] && cp "$CONFIG_PATH" "$CONFIG_PATH.bak-$STAMP"
[[ -f "$AUTH_PATH" ]] && cp "$AUTH_PATH" "$AUTH_PATH.bak-$STAMP"

BASE_URL="$BASE_URL" API_KEY="$API_KEY" CONFIG_PATH="$CONFIG_PATH" AUTH_PATH="$AUTH_PATH" python3 - <<'PY'
import json
import os
from pathlib import Path


def set_toml_value(lines, section, key, value):
    current_section = None
    section_found = section is None
    key_set = False
    out = []

    for line in lines:
        stripped = line.strip()
        is_header = stripped.startswith("[") and stripped.endswith("]")

        if is_header:
            if section_found and not key_set and current_section == section:
                out.append(f"{key} = {value}")
                key_set = True
            current_section = stripped.strip("[]")
            if current_section == section:
                section_found = True
            out.append(line)
            continue

        in_target = current_section is None if section is None else current_section == section
        if in_target and stripped.startswith(f"{key}") and "=" in stripped:
            if not key_set:
                out.append(f"{key} = {value}")
                key_set = True
            continue

        out.append(line)

    if not section_found and section is not None:
        if out and out[-1].strip():
            out.append("")
        out.append(f"[{section}]")
        out.append(f"{key} = {value}")
    elif not key_set:
        out.append(f"{key} = {value}")

    return out


config_path = Path(os.environ["CONFIG_PATH"])
auth_path = Path(os.environ["AUTH_PATH"])
base_url = os.environ["BASE_URL"]
api_key = os.environ["API_KEY"]

lines = config_path.read_text(encoding="utf-8").splitlines() if config_path.exists() else []

for section, key, value in [
    (None, "model_provider", '"OpenAI"'),
    (None, "model", '"gpt-5.5"'),
    (None, "review_model", '"gpt-5.5"'),
    (None, "model_reasoning_effort", '"high"'),
    (None, "disable_response_storage", "true"),
    (None, "network_access", '"enabled"'),
    (None, "windows_wsl_setup_acknowledged", "true"),
    ("model_providers.OpenAI", "name", '"OpenAI"'),
    ("model_providers.OpenAI", "base_url", json.dumps(base_url)),
    ("model_providers.OpenAI", "wire_api", '"responses"'),
    ("model_providers.OpenAI", "requires_openai_auth", "true"),
    ("features", "goals", "false"),
]:
    lines = set_toml_value(lines, section, key, value)

config_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")

try:
    auth = json.loads(auth_path.read_text(encoding="utf-8")) if auth_path.exists() else {}
    if not isinstance(auth, dict):
        auth = {}
except Exception:
    auth = {}

auth["OPENAI_API_KEY"] = api_key
auth_path.write_text(json.dumps(auth, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

echo
echo "Updated:"
echo "  $CONFIG_PATH"
echo "  $AUTH_PATH"
echo "Backups were created for existing files."
echo "Done."
