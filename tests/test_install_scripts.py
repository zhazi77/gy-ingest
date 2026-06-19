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
            self.assertIn("请完全退出并重新打开 Codex", script)
            self.assertIn("restore", script)

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
        self.assertIn('错误：需要 python3', bash)
        self.assertLess(bash.index('command -v python3'), bash.index('mkdir -p "$CODEX_HOME"'))

    def test_shell_scripts_are_kept_lf_for_unix(self):
        attrs = (ROOT / ".gitattributes").read_text(encoding="utf-8")

        self.assertIn("*.sh text eol=lf", attrs)

    def test_powershell_installer_hides_api_key_input(self):
        powershell_path = ROOT / "scripts" / "install-codex-sub2api.ps1"
        powershell = powershell_path.read_text(encoding="utf-8")

        self.assertFalse(powershell_path.read_bytes().startswith(b"\xef\xbb\xbf"))
        self.assertIn("Read-Host \"请粘贴 API key（输入时不会显示）\" -AsSecureString", powershell)
        self.assertIn("SecureStringToBSTR", powershell)
        self.assertIn("ZeroFreeBSTR", powershell)

    def test_install_scripts_create_backups_before_writing(self):
        powershell = (ROOT / "scripts" / "install-codex-sub2api.ps1").read_text(encoding="utf-8")
        bash = (ROOT / "scripts" / "install-codex-sub2api.sh").read_text(encoding="utf-8")

        self.assertIn("Backup-IfExists $configPath", powershell)
        self.assertIn("Backup-IfExists $authPath", powershell)
        self.assertIn('CONFIG_BACKUP="$CONFIG_PATH.bak-$STAMP"', bash)
        self.assertIn('AUTH_BACKUP="$AUTH_PATH.bak-$STAMP"', bash)
        self.assertIn('cp "$CONFIG_PATH" "$CONFIG_BACKUP"', bash)
        self.assertIn('cp "$AUTH_PATH" "$AUTH_BACKUP"', bash)

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
            env["CODEX_SUB2API_KEY"] = "sk-test"
            env["CODEX_SUB2API_CONFIRM"] = "yes"
            subprocess.run(
                [
                    "powershell",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-Command",
                    (
                        "$script = [System.Text.Encoding]::UTF8.GetString("
                        f"[System.IO.File]::ReadAllBytes('{ROOT / 'scripts' / 'install-codex-sub2api.ps1'}')); "
                        "Invoke-Expression $script"
                    ),
                ],
                env=env,
                check=True,
                capture_output=True,
            )

            config = (codex / "config.toml").read_text(encoding="utf-8")
            auth = json.loads((codex / "auth.json").read_text(encoding="utf-8"))
            restore_exists = (codex / "restore-sub2api-backup.ps1").exists()

        self.assertNotIn("[]", config)
        self.assertIn('foo = "keep"', config)
        self.assertIn("old_feature = true", config)
        self.assertIn('model_reasoning_effort = "high"', config)
        self.assertIn("goals = false", config)
        self.assertIn('base_url = "https://771to8vw3580.vicp.fun"', config)
        self.assertEqual(auth["OTHER"], "keep")
        self.assertEqual(auth["OPENAI_API_KEY"], "sk-test")
        self.assertTrue(restore_exists)

    @unittest.skipIf(shutil.which("powershell") is None, "PowerShell is not available")
    def test_powershell_installer_switches_chatgpt_auth_to_api_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            codex = root / ".codex"
            codex.mkdir()
            (codex / "auth.json").write_text(
                json.dumps(
                    {
                        "auth_mode": "chatgpt",
                        "OPENAI_API_KEY": None,
                        "tokens": {"access_token": "old"},
                        "last_refresh": "2026-06-19T00:00:00Z",
                        "OTHER": "keep",
                    }
                )
                + "\n",
                encoding="utf-8",
            )

            env = os.environ.copy()
            env["USERPROFILE"] = str(root)
            env["CODEX_SUB2API_KEY"] = "sk-test"
            result = subprocess.run(
                [
                    "powershell",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-Command",
                    (
                        "$script = [System.Text.Encoding]::UTF8.GetString("
                        f"[System.IO.File]::ReadAllBytes('{ROOT / 'scripts' / 'install-codex-sub2api.ps1'}')); "
                        "Invoke-Expression $script"
                    ),
                ],
                env=env,
                check=True,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
            )

            auth = json.loads((codex / "auth.json").read_text(encoding="utf-8"))

        self.assertEqual(auth["auth_mode"], "api_key")
        self.assertEqual(auth["OPENAI_API_KEY"], "sk-test")
        self.assertEqual(auth["OTHER"], "keep")
        self.assertNotIn("tokens", auth)
        self.assertNotIn("last_refresh", auth)
        self.assertIn("检测到 Codex 已经登录过 ChatGPT 账号", result.stdout)
        self.assertIn("将把 Codex 切换为 API key 模式", result.stdout)
        self.assertIn("请完全退出并重新打开 Codex", result.stdout)

    def test_install_scripts_create_restore_helpers(self):
        powershell = (ROOT / "scripts" / "install-codex-sub2api.ps1").read_text(encoding="utf-8")
        bash = (ROOT / "scripts" / "install-codex-sub2api.sh").read_text(encoding="utf-8")

        self.assertIn("restore-sub2api-backup.ps1", powershell)
        self.assertIn("Copy-Item", powershell)
        self.assertIn("restore-sub2api-backup.sh", bash)
        self.assertIn("cp ", bash)

    def test_static_server_declares_utf8_for_install_scripts(self):
        server = (ROOT / "scripts" / "codex_installer_site.py").read_text(encoding="utf-8")

        self.assertIn("charset=utf-8", server)
        self.assertIn(".ps1", server)
        self.assertIn(".sh", server)


if __name__ == "__main__":
    unittest.main()
