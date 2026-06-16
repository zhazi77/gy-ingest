import json
import tempfile
import unittest
from pathlib import Path

from scripts.init_wiki import init_wiki


class InitWikiTests(unittest.TestCase):
    def test_init_wiki_creates_expected_layout_and_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "gy-wiki"

            init_wiki(root)

            manifest = json.loads((root / "index" / "manifest.json").read_text(encoding="utf-8"))
            self.assertTrue((root / "raw" / "rss" / "feeds").is_dir())
            self.assertTrue((root / "raw" / "rss" / "items").is_dir())
            self.assertTrue((root / "inbox" / "rss").is_dir())
            self.assertEqual(manifest["rss"]["seen"], {})


if __name__ == "__main__":
    unittest.main()
