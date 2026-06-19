#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://771to8vw3580.vicp.fun}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
PYTHON_BIN="${PYTHON_BIN:-}"

echo "Codex Sub2API 安装器"
echo "Base URL: $BASE_URL"
printf "请粘贴 API key（输入时不会显示）: "
IFS= read -r -s API_KEY
echo
API_KEY="$(printf '%s' "$API_KEY" | tr -d '\r\n ')"

if [[ -z "$API_KEY" ]]; then
  echo "错误：API key 为空。" >&2
  exit 2
fi

if [[ -z "$PYTHON_BIN" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "错误：需要 python3 来合并 Codex 配置。" >&2
    exit 3
  fi
fi

mkdir -p "$CODEX_HOME"
CONFIG_PATH="$CODEX_HOME/config.toml"
AUTH_PATH="$CODEX_HOME/auth.json"
RESTORE_PATH="$CODEX_HOME/restore-sub2api-backup.sh"
STAMP="$(date +%Y%m%d%H%M%S)"

AUTH_STATE="$(AUTH_PATH="$AUTH_PATH" "$PYTHON_BIN" - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ["AUTH_PATH"])
try:
    auth = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
except Exception:
    auth = {}

if isinstance(auth, dict) and (auth.get("auth_mode") == "chatgpt" or "tokens" in auth):
    print("chatgpt")
else:
    print("none")
PY
)"

if [[ "$AUTH_STATE" == "chatgpt" ]]; then
  echo "检测到 Codex 已经登录过 ChatGPT 账号。"
  echo "将把 Codex 切换为 API key 模式，并从 auth.json 中移除旧的 ChatGPT 登录缓存。"
  echo "安装完成后，请完全退出并重新打开 Codex，让新的认证配置生效。"
  if [[ -z "${CODEX_SUB2API_CONFIRM:-}" ]]; then
    printf "是否继续？直接回车表示继续，[n] 取消: "
    IFS= read -r answer
    case "$answer" in
      n|N|no|NO|No)
        echo "已取消，没有修改文件。"
        exit 4
        ;;
    esac
  fi
else
  echo "未检测到已有的 Codex ChatGPT 登录态。"
fi

CONFIG_BACKUP=""
AUTH_BACKUP=""
if [[ -f "$CONFIG_PATH" ]]; then
  CONFIG_BACKUP="$CONFIG_PATH.bak-$STAMP"
  cp "$CONFIG_PATH" "$CONFIG_BACKUP"
fi
if [[ -f "$AUTH_PATH" ]]; then
  AUTH_BACKUP="$AUTH_PATH.bak-$STAMP"
  cp "$AUTH_PATH" "$AUTH_BACKUP"
fi

{
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  echo 'restored=false'
  if [[ -n "$CONFIG_BACKUP" ]]; then
    printf 'cp %q %q\n' "$CONFIG_BACKUP" "$CONFIG_PATH"
    echo 'restored=true'
  fi
  if [[ -n "$AUTH_BACKUP" ]]; then
    printf 'cp %q %q\n' "$AUTH_BACKUP" "$AUTH_PATH"
    echo 'restored=true'
  fi
  echo 'if [[ "$restored" == true ]]; then'
  echo '  echo "已从备份恢复 Codex 配置和认证文件。"'
  echo '  echo "请完全退出并重新打开 Codex，让恢复后的配置生效。"'
  echo 'else'
  echo '  echo "没有可恢复的备份文件。"'
  echo 'fi'
} > "$RESTORE_PATH"
chmod +x "$RESTORE_PATH"

BASE_URL="$BASE_URL" API_KEY="$API_KEY" CONFIG_PATH="$CONFIG_PATH" AUTH_PATH="$AUTH_PATH" "$PYTHON_BIN" - <<'PY'
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

auth.pop("tokens", None)
auth.pop("last_refresh", None)
auth["auth_mode"] = "api_key"
auth["OPENAI_API_KEY"] = api_key
auth_path.write_text(json.dumps(auth, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

echo
echo "已更新："
echo "  $CONFIG_PATH"
echo "  $AUTH_PATH"
echo "如需恢复到安装前的配置，请运行："
echo "  bash \"$RESTORE_PATH\""
echo "已为现有配置文件创建备份。"
echo "请完全退出并重新打开 Codex，让新的配置和 API key 认证模式生效。"
echo "完成。"
