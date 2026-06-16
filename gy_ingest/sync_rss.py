from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Callable
from urllib.request import Request, urlopen
from xml.etree import ElementTree


USER_AGENT = "gy-ingest/0.1 (+https://github.com/zhazi77/gy-ingest)"


def load_sources(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".json":
        data = json.loads(text)
        return _normalize_sources(data.get("sources", data))
    return _normalize_sources(_parse_simple_sources_yaml(text))


def _parse_simple_sources_yaml(text: str) -> list[dict]:
    sources: list[dict] = []
    current: dict | None = None

    for raw_line in text.splitlines():
        line = raw_line.split("#", 1)[0].rstrip()
        if not line.strip() or line.strip() == "sources:":
            continue

        stripped = line.strip()
        if stripped.startswith("- "):
            if current:
                sources.append(current)
            current = {}
            stripped = stripped[2:].strip()
            if stripped:
                key, value = _split_yaml_key_value(stripped)
                current[key] = _parse_scalar(value)
            continue

        if current is None:
            continue
        key, value = _split_yaml_key_value(stripped)
        current[key] = _parse_scalar(value)

    if current:
        sources.append(current)
    return sources


def _split_yaml_key_value(line: str) -> tuple[str, str]:
    if ":" not in line:
        raise ValueError(f"Invalid sources.yaml line: {line}")
    key, value = line.split(":", 1)
    return key.strip(), value.strip()


def _parse_scalar(value: str):
    value = value.strip().strip('"').strip("'")
    if "," in value:
        return [part.strip() for part in value.split(",") if part.strip()]
    return value


def _normalize_sources(sources: list[dict]) -> list[dict]:
    normalized = []
    for source in sources:
        if source.get("type", "rss") != "rss":
            continue
        name = source.get("name")
        url = source.get("url")
        if not name or not url:
            raise ValueError(f"RSS source needs name and url: {source}")
        normalized.append(
            {
                "name": str(name),
                "type": "rss",
                "url": str(url),
                "tags": source.get("tags", []),
            }
        )
    return normalized


def fetch_url(url: str) -> str:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=30) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return response.read().decode(charset, errors="replace")


def parse_feed(xml_text: str) -> list[dict]:
    root = ElementTree.fromstring(xml_text.encode("utf-8"))
    root_name = _local_name(root.tag)
    if root_name == "rss":
        return _parse_rss(root)
    if root_name == "feed":
        return _parse_atom(root)
    raise ValueError(f"Unsupported feed root: {root.tag}")


def _parse_rss(root: ElementTree.Element) -> list[dict]:
    items = []
    channel = root.find("channel")
    if channel is None:
        channel = root
    for item in channel.findall("item"):
        title = _child_text(item, "title")
        url = _child_text(item, "link")
        guid = _child_text(item, "guid") or url
        if not title or not url:
            continue
        items.append(
            {
                "title": title,
                "url": url,
                "guid": guid,
                "summary": _child_text(item, "description"),
                "published_at": _child_text(item, "pubDate"),
            }
        )
    return items


def _parse_atom(root: ElementTree.Element) -> list[dict]:
    items = []
    for entry in _children(root, "entry"):
        title = _child_text(entry, "title")
        url = _atom_link(entry)
        guid = _child_text(entry, "id") or url
        if not title or not url:
            continue
        items.append(
            {
                "title": title,
                "url": url,
                "guid": guid,
                "summary": _child_text(entry, "summary") or _child_text(entry, "content"),
                "published_at": _child_text(entry, "published") or _child_text(entry, "updated"),
            }
        )
    return items


def _children(element: ElementTree.Element, name: str):
    return [child for child in list(element) if _local_name(child.tag) == name]


def _child_text(element: ElementTree.Element, name: str) -> str:
    for child in list(element):
        if _local_name(child.tag) == name:
            return "".join(child.itertext()).strip()
    return ""


def _atom_link(entry: ElementTree.Element) -> str:
    fallback = ""
    for child in list(entry):
        if _local_name(child.tag) != "link":
            continue
        href = child.attrib.get("href", "")
        rel = child.attrib.get("rel", "alternate")
        if rel == "alternate" and href:
            return href
        fallback = fallback or href
    return fallback


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def sync_sources(
    sources: list[dict],
    wiki_root: Path,
    *,
    now: datetime | None = None,
    fetcher: Callable[[str], str] = fetch_url,
) -> dict:
    now = now or datetime.now(timezone.utc)
    manifest = _load_manifest(wiki_root)
    new_entries = []
    feed_files_written = 0

    for source in sources:
        source_name = source["name"]
        xml_text = fetcher(source["url"])
        feed_path = _write_feed_xml(wiki_root, source_name, xml_text, now)
        feed_files_written += 1

        for item in parse_feed(xml_text):
            stable_key = item.get("guid") or item["url"]
            if stable_key in manifest["rss"]["seen"]:
                continue
            entry = _build_entry(source, item, feed_path, now, stable_key)
            item_path = _write_item_json(wiki_root, source_name, entry, now)
            entry["item_path"] = str(item_path.relative_to(wiki_root)).replace("\\", "/")
            manifest["rss"]["seen"][stable_key] = {
                "id": entry["id"],
                "source_name": source_name,
                "captured_at": entry["captured_at"],
                "path": entry["item_path"],
            }
            new_entries.append(entry)

    if new_entries:
        _write_inbox(wiki_root, new_entries, now)
    _save_manifest(wiki_root, manifest, now)

    return {"new_items": len(new_entries), "feed_files": feed_files_written}


def _load_manifest(wiki_root: Path) -> dict:
    path = wiki_root / "index" / "manifest.json"
    if not path.exists():
        return {"rss": {"seen": {}}, "updated_at": None}
    manifest = json.loads(path.read_text(encoding="utf-8"))
    manifest.setdefault("rss", {}).setdefault("seen", {})
    return manifest


def _save_manifest(wiki_root: Path, manifest: dict, now: datetime) -> None:
    manifest["updated_at"] = _iso(now)
    path = wiki_root / "index" / "manifest.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _write_feed_xml(wiki_root: Path, source_name: str, xml_text: str, now: datetime) -> Path:
    path = wiki_root / "raw" / "rss" / "feeds" / source_name / f"{_stamp(now)}.xml"
    if path.exists():
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(xml_text, encoding="utf-8")
    return path


def _build_entry(source: dict, item: dict, feed_path: Path, now: datetime, stable_key: str) -> dict:
    entry_id = hashlib.sha256(stable_key.encode("utf-8")).hexdigest()[:16]
    return {
        "id": entry_id,
        "source_type": "rss",
        "source_name": source["name"],
        "source_url": source["url"],
        "title": item["title"],
        "url": item["url"],
        "guid": item.get("guid", ""),
        "summary": item.get("summary", ""),
        "content": "",
        "published_at": _normalize_datetime(item.get("published_at", "")),
        "captured_at": _iso(now),
        "raw_feed_path": str(feed_path).replace("\\", "/"),
        "tags": source.get("tags", []),
        "status": "raw",
    }


def _write_item_json(wiki_root: Path, source_name: str, entry: dict, now: datetime) -> Path:
    title_slug = _slugify(entry["title"])
    path = (
        wiki_root
        / "raw"
        / "rss"
        / "items"
        / source_name
        / f"{now:%Y}"
        / f"{now:%m}"
        / f"{entry['id']}-{title_slug}.json"
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(entry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


def _write_inbox(wiki_root: Path, entries: list[dict], now: datetime) -> None:
    path = wiki_root / "inbox" / "rss" / f"{now:%Y-%m-%d}.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    existing = path.read_text(encoding="utf-8") if path.exists() else f"# RSS Inbox {now:%Y-%m-%d}\n\n"
    lines = [existing.rstrip(), ""]
    for entry in entries:
        lines.append(f"- [{entry['title']}]({entry['url']})")
        lines.append(f"  - Source: `{entry['source_name']}`")
        if entry.get("published_at"):
            lines.append(f"  - Published: `{entry['published_at']}`")
        lines.append(f"  - Item: `{entry['item_path']}`")
    path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def _normalize_datetime(value: str) -> str:
    value = value.strip()
    if not value:
        return ""
    try:
        return _iso(parsedate_to_datetime(value))
    except (TypeError, ValueError, IndexError):
        return value


def _slugify(value: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", value.lower()).strip("-")
    return slug[:70] or "item"


def _stamp(now: datetime) -> str:
    return now.strftime("%Y%m%dT%H%M%SZ")


def _iso(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def git_commit_and_push(repo: Path, message: str, push: bool) -> bool:
    if not _git_has_changes(repo):
        return False
    _run_git(repo, "add", ".")
    _run_git(repo, "commit", "-m", message)
    if push:
        _run_git(repo, "push")
    return True


def _git_has_changes(repo: Path) -> bool:
    result = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=repo,
        check=True,
        text=True,
        capture_output=True,
    )
    return bool(result.stdout.strip())


def _run_git(repo: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=repo, check=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Sync RSS sources into a gy-wiki repository.")
    parser.add_argument("--sources", type=Path, default=Path("config/sources.yaml"))
    parser.add_argument("--wiki-root", type=Path, required=True)
    parser.add_argument("--git", action="store_true", help="Commit changes in the wiki repository.")
    parser.add_argument("--push", action="store_true", help="Push committed wiki changes.")
    args = parser.parse_args(argv)

    sources = load_sources(args.sources)
    result = sync_sources(sources, args.wiki_root)
    print(f"Synced {len(sources)} source(s); new RSS items: {result['new_items']}")

    if args.git:
        committed = git_commit_and_push(
            args.wiki_root,
            f"sync rss {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}",
            args.push,
        )
        print("Committed wiki changes." if committed else "No wiki changes to commit.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
