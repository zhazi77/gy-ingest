#!/usr/bin/env bash
set -euo pipefail

URL="${1:-https://771to8vw3580.vicp.fun}"
TOKEN_FILE="${2:-/home/zhazi/workspace/linux-deploy-package/test_sk.txt}"

if [[ ! -f "$TOKEN_FILE" ]]; then
  echo "ERROR: token file not found: $TOKEN_FILE" >&2
  exit 2
fi

TOKEN="$(tr -d '\r\n ' < "$TOKEN_FILE")"
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: token file is empty: $TOKEN_FILE" >&2
  exit 2
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

echo "== Sub2API tunnel check =="
echo "url: $URL"
echo "token_file: $TOKEN_FILE"
echo

curl -sS -o "$tmp" -w 'http_code=%{http_code} time=%{time_total} bytes=%{size_download}\n' \
  -H "Authorization: Bearer ${TOKEN}" \
  "${URL%/}/v1/models"

python3 - "$tmp" <<'PY'
import json
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(errors="replace")
print("body_prefix=", text[:240].replace("\n", " "))
try:
    data = json.loads(text)
except Exception as exc:
    print("json_parse_error=", type(exc).__name__)
    raise SystemExit(1)

code = data.get("code")
message = data.get("message")
models = data.get("data", [])
print("code=", code)
print("message=", message)
print("model_count=", len(models) if isinstance(models, list) else 0)
print("first_models=", [m.get("id") for m in models[:5]] if isinstance(models, list) else [])

if code == "INSUFFICIENT_BALANCE":
    print("RESULT=reachable_authenticated_but_insufficient_balance")
elif isinstance(models, list):
    print("RESULT=reachable_authenticated")
else:
    print("RESULT=reachable_unexpected_response")
PY
