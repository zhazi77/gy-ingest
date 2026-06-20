#!/usr/bin/env bash
set -euo pipefail

INGEST_DIR="${INGEST_DIR:-$HOME/gy-ingest}"
WIKI_DIR="${WIKI_DIR:-$HOME/gy-wiki}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

echo "== gy-ingest health check =="
echo "ingest: $INGEST_DIR"
echo "wiki:   $WIKI_DIR"
echo

cd "$INGEST_DIR"

echo "== Environment =="
hostname
git --version
"$PYTHON_BIN" --version
echo

echo "== Pull gy-ingest =="
git pull --ff-only
echo

echo "== Unit tests =="
"$PYTHON_BIN" -m unittest discover -s tests
echo

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

echo "== Temporary sync test =="
"$PYTHON_BIN" scripts/init_wiki.py "$tmp_dir/wiki"
timeout 180 "$PYTHON_BIN" -m gy_ingest.sync_rss --wiki-root "$tmp_dir/wiki"
echo

echo "== Real wiki status =="
cd "$WIKI_DIR"
git status --short --branch
echo

echo "OK: tests passed and RSS sync completed in a temporary wiki."
