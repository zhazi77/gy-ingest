from __future__ import annotations

import argparse
from pathlib import Path


DIRECTORIES = [
    "raw/rss/feeds",
    "raw/rss/items",
    "raw/html",
    "raw/voice",
    "raw/ai-chat",
    "inbox/rss",
    "processed/summaries",
    "processed/cards",
    "index",
]


README = """# gy-wiki

Personal knowledge repository.

## Layout

- `raw/`: unmodified captured source material.
- `inbox/`: newly captured items waiting for review.
- `processed/`: summaries, cards, tags, and other derived material.
- `index/`: manifests and source state.
"""


def init_wiki(root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    for directory in DIRECTORIES:
        path = root / directory
        path.mkdir(parents=True, exist_ok=True)
        keep = path / ".gitkeep"
        if not keep.exists():
            keep.write_text("", encoding="utf-8")

    readme = root / "README.md"
    if not readme.exists():
        readme.write_text(README, encoding="utf-8")

    manifest = root / "index" / "manifest.json"
    if not manifest.exists():
        manifest.write_text('{\n  "rss": {\n    "seen": {}\n  },\n  "updated_at": null\n}\n', encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Initialize a gy-wiki repository layout.")
    parser.add_argument("wiki_root", type=Path)
    args = parser.parse_args()
    init_wiki(args.wiki_root)
    print(f"Initialized {args.wiki_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
