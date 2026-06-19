import unittest
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class InstallScriptTests(unittest.TestCase):
    def test_install_scripts_use_expected_codex_defaults(self):
        powershell = (ROOT / "scripts" / "install-codex-sub2api.ps1").read_text(encoding="utf-8")
        bash = (ROOT / "scripts" / "install-codex-sub2api.sh").read_text(encoding="utf-8")

        for script in (powershell, bash):
            self.assertIn("https://771to8vw3580.vicp.fun", script)
            self.assertNotIn("https://771to8vw3580.vicp.fun/v1", script)
            self.assertIn("model_reasoning_effort", script)
            self.assertIn('"high"', script)
            self.assertIn("goals", script)
            self.assertIn("false", script)
            self.assertIn("OPENAI_API_KEY", script)

    def test_unix_installer_targets_home_codex_directory(self):
        bash = (ROOT / "scripts" / "install-codex-sub2api.sh").read_text(encoding="utf-8")

        self.assertIn('CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"', bash)
        self.assertIn('CONFIG_PATH="$CODEX_HOME/config.toml"', bash)
        self.assertIn('AUTH_PATH="$CODEX_HOME/auth.json"', bash)
        self.assertIn('mkdir -p "$CODEX_HOME"', bash)

    def test_unix_installer_checks_for_python3_before_writing(self):
        bash = (ROOT / "scripts" / "install-codex-sub2api.sh").read_text(encoding="utf-8")

        self.assertIn('PYTHON_BIN="${PYTHON_BIN:-}"', bash)
        self.assertIn('command -v python3', bash)
        self.assertIn('ERROR: python3 is required', bash)
        self.assertLess(bash.index('command -v python3'), bash.index('mkdir -p "$CODEX_HOME"'))

    def test_shell_scripts_are_kept_lf_for_unix(self):
        attrs = (ROOT / ".gitattributes").read_text(encoding="utf-8")

        self.assertIn("*.sh text eol=lf", attrs)

    def test_install_scripts_create_backups_before_writing(self):
        powershell = (ROOT / "scripts" / "install-codex-sub2api.ps1").read_text(encoding="utf-8")
        bash = (ROOT / "scripts" / "install-codex-sub2api.sh").read_text(encoding="utf-8")

        self.assertIn("Backup-IfExists $configPath", powershell)
        self.assertIn("Backup-IfExists $authPath", powershell)
        self.assertIn("cp \"$CONFIG_PATH\" \"$CONFIG_PATH.bak-$STAMP\"", bash)
        self.assertIn("cp \"$AUTH_PATH\" \"$AUTH_PATH.bak-$STAMP\"", bash)

    @unittest.skipIf(shutil.which("powershell") is None, "PowerShell is not available")
    def test_powershell_installer_merges_existing_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            codex = root / ".codex"
            codex.mkdir()
            (codex / "config.toml").write_text(
                'foo = "keep"\nmodel_reasoning_effort = "low"\n\n[features]\nold_feature = true\n',
                encoding="utf-8",
            )
            (codex / "auth.json").write_text('{"OTHER":"keep"}\n', encoding="utf-8")

            env = os.environ.copy()
            env["USERPROFILE"] = str(root)
            subprocess.run(
                [
                    "powershell",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(ROOT / "scripts" / "install-codex-sub2api.ps1"),
                ],
                input="sk-test\n",
                text=True,
                env=env,
                check=True,
                capture_output=True,
            )

            config = (codex / "config.toml").read_text(encoding="utf-8")
            auth = json.loads((codex / "auth.json").read_text(encoding="utf-8"))

        self.assertNotIn("[]", config)
        self.assertIn('foo = "keep"', config)
        self.assertIn("old_feature = true", config)
        self.assertIn('model_reasoning_effort = "high"', config)
        self.assertIn("goals = false", config)
        self.assertIn('base_url = "https://771to8vw3580.vicp.fun"', config)
        self.assertEqual(auth["OTHER"], "keep")
        self.assertEqual(auth["OPENAI_API_KEY"], "sk-test")


if __name__ == "__main__":
    unittest.main()
