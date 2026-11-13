"""Offline new-object registration checks (no network or TTS process)."""
import importlib.util
import json
import subprocess
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "register_new_objects.py"
spec = importlib.util.spec_from_file_location("register_new_objects", SCRIPT)
reg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reg)


class RegisterNewObjectsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "New").mkdir()
        (self.root / "live" / "global").mkdir(parents=True)
        (self.root / "live" / "objects").mkdir()
        (self.root / "docs").mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def file(self, relative, content):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def test_move_pair_and_unchanged_bytes(self):
        lua = self.file("New/Some Counter.abc123.lua", b"function onLoad()\r\nend\r\n")
        xml = self.file("New/Some Counter.abc123.xml", b"<Panel />\n")
        self.assertEqual(reg.register(self.root, apply=True), 0)
        dest = self.root / "live/objects/counters-and-trackers/Some Counter.abc123.lua"
        self.assertEqual(dest.read_bytes(), b"function onLoad()\r\nend\r\n")
        self.assertFalse(lua.exists())
        self.assertFalse(xml.exists())
        obj = json.loads((self.root / reg.REGISTRY).read_text())["objects"]
        self.assertEqual(obj[0]["guid"], "abc123")
        self.assertEqual(set(obj[0]["files"]), {"lua", "xml"})
        self.assertEqual(reg.register(self.root, apply=True), 0)

    def test_dry_run_does_not_move(self):
        obj = self.file("New/Mystery.aabbcc.lua", b"-- unknown")
        self.assertEqual(reg.register(self.root, apply=False), 0)
        self.assertTrue(obj.is_file())
        self.assertFalse((self.root / reg.REGISTRY).exists())

    def test_conflicting_guid_keeps_both(self):
        original = self.file("live/objects/utilities/Gadget.123abc.lua", b"old")
        incoming = self.file("New/Gadget.123abc.lua", b"new")
        with self.assertRaisesRegex(ValueError, "contents differ"):
            reg.register(self.root, apply=True)
        self.assertEqual(original.read_bytes(), b"old")
        self.assertEqual(incoming.read_bytes(), b"new")

    def test_identical_duplicate_removed(self):
        original = self.file("live/objects/utilities/Gadget.123abc.lua", b"same")
        incoming = self.file("New/Gadget.123abc.lua", b"same")
        self.assertEqual(reg.register(self.root, apply=True), 0)
        self.assertFalse(incoming.exists())
        self.assertEqual(original.read_bytes(), b"same")

    def test_duplicate_guid_in_inbox_rejected(self):
        self.file("New/a/Gadget.123abc.lua", b"a")
        self.file("New/b/Gadget.123abc.lua", b"b")
        with self.assertRaisesRegex(ValueError, "Duplicate GUID"):
            reg.prepare(self.root)

    def test_existing_xml_companion_uses_existing_category(self):
        self.file("live/objects/automation/Timer.123abc.lua", b"lua")
        self.file("New/Timer.123abc.xml", b"<Text />")
        self.assertEqual(reg.register(self.root, apply=True), 0)
        self.assertTrue((self.root / "live/objects/automation/Timer.123abc.xml").exists())

    def test_global_not_auto_imported(self):
        src = self.file("New/Global.-1.lua", b"new global")
        with self.assertRaisesRegex(ValueError, "must be reconciled"):
            reg.register(self.root, apply=True)
        self.assertTrue(src.exists())

    def test_scriptless_savegame_guid(self):
        save = self.file("savegame.json", json.dumps({"ObjectStates": [
            {"GUID": "c0ffee", "Name": "Custom_Model", "Nickname": "Mystery Prop", "Tags": ["White", "Battlefield"]}
        ]}).encode())
        self.assertEqual(reg.register(self.root, apply=True, save=save, guids=["c0ffee"]), 0)
        obj = json.loads((self.root / reg.REGISTRY).read_text())["objects"][0]
        self.assertTrue(obj["manual"])
        self.assertEqual(obj["savegame"]["tags"], ["White", "Battlefield"])
        self.assertEqual(obj["savegame"]["metadata_source"], "savegame.json")
        self.assertEqual(reg.register(self.root, apply=True), 0)
        retained = json.loads((self.root / reg.REGISTRY).read_text())["objects"][0]
        self.assertEqual(retained, obj)

    def test_scriptless_wrong_save_rejected(self):
        save = self.file("savegame.json", b'{"ObjectStates": []}')
        with self.assertRaisesRegex(ValueError, "not found"):
            reg.register(self.root, apply=True, save=save, guids=["aaaaaa"])
        self.assertFalse((self.root / reg.REGISTRY).exists())

    def test_publish_bracketed_filename_with_local_remote(self):
        def run(*args, cwd=None):
            return subprocess.run(["git", *args], cwd=cwd or self.root,
                                  capture_output=True, check=True, text=True).stdout.strip()

        run("init", "-b", "main")
        run("config", "user.name", "Test Bot")
        run("config", "user.email", "test@example.invalid")
        self.file("New/.gitkeep", b"")
        run("add", "-A")
        run("commit", "-m", "initial")
        with tempfile.TemporaryDirectory() as remote_dir:
            remote = Path(remote_dir) / "origin.git"
            run("init", "--bare", str(remote))
            run("remote", "add", "origin", str(remote))
            run("push", "-u", "origin", "main")
            self.file("New/[b]Some Counter[b].abc123.lua", b"function onLoad() end")
            self.assertEqual(reg.register(self.root, apply=True, publish=True), 0)
            self.assertTrue((self.root / "live/objects/counters-and-trackers/[b]Some Counter[b].abc123.lua").exists())
            self.assertEqual(run("rev-parse", "HEAD"), run("rev-parse", "origin/main"))
            self.assertEqual(run("status", "--porcelain"), "")

    def test_other_script_name_unclassified_not_guessed(self):
        self.file("New/Custom Object.654321.lua", b"script")
        self.assertEqual(reg.register(self.root, apply=True), 0)
        self.assertTrue((self.root / "live/objects/unclassified/Custom Object.654321.lua").exists())


if __name__ == "__main__":
    unittest.main()
