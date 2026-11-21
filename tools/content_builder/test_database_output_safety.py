"""Output safety regressions for the offline Quran database builder."""
from pathlib import Path
import os
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

import build_quran_db as builder


class OutputSafetyTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name) / "quran.db"
        self.original = b"previous database must survive"
        self.output.write_bytes(self.original)

    def assert_preserved(self):
        self.assertEqual(self.output.read_bytes(), self.original)
        self.assertEqual(list(self.output.parent.glob(".quran-build-*")), [])

    def test_missing_xml_preserves_output(self):
        with patch.object(builder, "XML_PATH", str(self.output.parent / "missing.xml")):
            with self.assertRaises(FileNotFoundError):
                builder.init_database(self.output)
        self.assert_preserved()

    def test_invalid_text_preserves_output(self):
        source = self.output.parent / "invalid.txt"
        source.write_text("test only\n", encoding="utf-8")
        with patch.object(builder, "UTHMANI_PATH", str(source)):
            with self.assertRaises(ValueError):
                builder.init_database(self.output)
        self.assert_preserved()

    def test_write_failure_preserves_output(self):
        with patch.object(builder.sqlite3, "connect", side_effect=sqlite3.OperationalError("test")):
            with self.assertRaises(sqlite3.OperationalError):
                builder.init_database(self.output)
        self.assert_preserved()

    def test_replacement_failure_preserves_output(self):
        with patch.object(builder.os, "replace", side_effect=PermissionError("test")):
            with self.assertRaises(PermissionError):
                builder.init_database(self.output)
        self.assert_preserved()

    def test_success_replaces_output_with_complete_database(self):
        builder.init_database(self.output)
        with sqlite3.connect(self.output) as conn:
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM ayah").fetchone()[0], 6236)
            self.assertEqual(conn.execute("PRAGMA integrity_check").fetchone()[0], "ok")
        self.assertEqual(list(self.output.parent.glob(".quran-build-*")), [])

    def test_relative_filename_is_supported(self):
        previous = os.getcwd()
        try:
            os.chdir(self.output.parent)
            builder.init_database("quran.db")
        finally:
            os.chdir(previous)
        with sqlite3.connect(self.output) as conn:
            self.assertEqual(conn.execute("SELECT COUNT(*) FROM ayah").fetchone()[0], 6236)


if __name__ == "__main__":
    unittest.main()
