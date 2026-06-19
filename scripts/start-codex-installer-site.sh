#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8091}"
SITE_DIR="${SITE_DIR:-$HOME/codex-installer-site}"
PID_FILE="$SITE_DIR/server.pid"
LOG_FILE="$SITE_DIR/server.log"

mkdir -p "$SITE_DIR"

if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" >/dev/null 2>&1; then
    echo "codex installer site already running: pid=$old_pid port=$PORT"
    exit 0
  fi
fi

cd "$SITE_DIR"
nohup python3 "$SITE_DIR/codex_installer_site.py" >"$LOG_FILE" 2>&1 &
pid="$!"
echo "$pid" > "$PID_FILE"

for _ in 1 2 3 4 5; do
  if curl -fsS "http://127.0.0.1:$PORT/install-codex-sub2api.sh" >/dev/null 2>&1; then
    echo "codex installer site running: pid=$pid port=$PORT dir=$SITE_DIR"
    exit 0
  fi
  sleep 1
done

if kill -0 "$pid" >/dev/null 2>&1; then
  echo "codex installer site started but health check failed; see $LOG_FILE" >&2
else
  echo "failed to start codex installer site; see $LOG_FILE" >&2
fi
exit 1
