import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from gy_ingest.sync_rss import load_sources, parse_feed, sync_sources


SAMPLE_RSS = """<?xml version="1.0"?>
<rss version="2.0">
  <channel>
    <title>Example Feed</title>
    <item>
      <title>First Post</title>
      <link>https://example.com/first</link>
      <guid>first-guid</guid>
      <description>Short summary</description>
      <pubDate>Tue, 16 Jun 2026 10:00:00 GMT</pubDate>
    </item>
  </channel>
</rss>
"""


class SyncRssTests(unittest.TestCase):
    def test_load_sources_reads_simple_yaml_source_list(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "sources.yaml"
            path.write_text(
                """
sources:
  - name: openai-news
    type: rss
    url: https://openai.com/news/rss.xml
    tags: ai, research
""".strip(),
                encoding="utf-8",
            )

            sources = load_sources(path)

        self.assertEqual(
            sources,
            [
                {
                    "name": "openai-news",
                    "type": "rss",
                    "url": "https://openai.com/news/rss.xml",
                    "tags": ["ai", "research"],
                }
            ],
        )

    def test_parse_feed_extracts_rss_items(self):
        items = parse_feed(SAMPLE_RSS)

        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["title"], "First Post")
        self.assertEqual(items[0]["url"], "https://example.com/first")
        self.assertEqual(items[0]["guid"], "first-guid")
        self.assertEqual(items[0]["summary"], "Short summary")
        self.assertEqual(items[0]["published_at"], "Tue, 16 Jun 2026 10:00:00 GMT")

    def test_sync_sources_writes_raw_feed_items_manifest_and_inbox_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            wiki_root = Path(tmp) / "gy-wiki"
            now = datetime(2026, 6, 16, 12, 30, tzinfo=timezone.utc)

            result = sync_sources(
                [{"name": "example", "type": "rss", "url": "https://example.com/feed.xml"}],
                wiki_root,
                now=now,
                fetcher=lambda url: SAMPLE_RSS,
            )
            second = sync_sources(
                [{"name": "example", "type": "rss", "url": "https://example.com/feed.xml"}],
                wiki_root,
                now=now,
                fetcher=lambda url: SAMPLE_RSS,
            )

            item_files = list((wiki_root / "raw" / "rss" / "items").rglob("*.json"))
            feed_files = list((wiki_root / "raw" / "rss" / "feeds").rglob("*.xml"))
            manifest = json.loads((wiki_root / "index" / "manifest.json").read_text(encoding="utf-8"))
            inbox = (wiki_root / "inbox" / "rss" / "2026-06-16.md").read_text(encoding="utf-8")

        self.assertEqual(result["new_items"], 1)
        self.assertEqual(second["new_items"], 0)
        self.assertEqual(len(item_files), 1)
        self.assertEqual(len(feed_files), 1)
        self.assertIn("first-guid", manifest["rss"]["seen"])
        self.assertIn("First Post", inbox)
        self.assertIn("https://example.com/first", inbox)


if __name__ == "__main__":
    unittest.main()
