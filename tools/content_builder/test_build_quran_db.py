"""
Integrity tests for build_quran_db.py (Section 7.1 constants + hizb/rub/sajdah correctness).
Uses the repo's canonical quran-data.xml markers with synthetic uthmani/tafseer
placeholders so the test is deterministic and does not depend on large text assets.
"""

import os
import sqlite3
import tempfile
import unittest

import build_quran_db as bq

DIR_PATH = os.path.dirname(os.path.abspath(__file__))
REAL_XML = os.path.join(DIR_PATH, "quran-data.xml")


class TestBuildQuranDb(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        # Synthetic uthmani text: exactly 6236 placeholder lines
        self.uthmani = os.path.join(self.tmp.name, "quran-uthmani.txt")
        with open(self.uthmani, "w", encoding="utf-8") as f:
            for i in range(6236):
                f.write("نص تجريبي للاختبار\n")
        self.tafseer = os.path.join(self.tmp.name, "ar.muyassar.txt")
        open(self.tafseer, "w", encoding="utf-8").close()
        self.db = os.path.join(self.tmp.name, "quran.db")

        self._orig = (bq.XML_PATH, bq.UTHMANI_PATH, bq.TAFSEER_PATH)
        bq.XML_PATH = REAL_XML
        bq.UTHMANI_PATH = self.uthmani
        bq.TAFSEER_PATH = self.tafseer
        self.addCleanup(self._restore)

    def _restore(self):
        bq.XML_PATH, bq.UTHMANI_PATH, bq.TAFSEER_PATH = self._orig

    def _build(self):
        bq.init_database(self.db)
        conn = sqlite3.connect(self.db)
        self.addCleanup(conn.close)
        return conn

    def test_integrity_constants(self):
        conn = self._build()
        cur = conn.cursor()
        self.assertEqual(cur.execute("SELECT COUNT(*) FROM surah").fetchone()[0], 114)
        self.assertEqual(cur.execute("SELECT COUNT(*) FROM ayah").fetchone()[0], 6236)
        self.assertEqual(cur.execute("SELECT COUNT(*) FROM reciter").fetchone()[0], 35)
        self.assertEqual(cur.execute("SELECT MIN(page), MAX(page) FROM ayah").fetchone(), (1, 604))
        self.assertEqual(cur.execute("SELECT MIN(juz), MAX(juz) FROM ayah").fetchone(), (1, 30))

    def test_hizb_and_rub_ranges_complete(self):
        conn = self._build()
        cur = conn.cursor()
        hizbs = {r[0] for r in cur.execute("SELECT DISTINCT hizb FROM ayah")}
        rubs = {r[0] for r in cur.execute("SELECT DISTINCT rub FROM ayah")}
        self.assertEqual(hizbs, set(range(1, 61)), "hizb must cover exactly 1..60")
        self.assertEqual(rubs, set(range(1, 241)), "rub must cover exactly 1..240")

    def test_hizb_rub_monotonic_and_consistent(self):
        conn = self._build()
        cur = conn.cursor()
        rows = cur.execute("SELECT id, hizb, rub FROM ayah ORDER BY id").fetchall()
        prev = (0, 0)
        for _id, hizb, rub in rows:
            self.assertGreaterEqual((hizb, rub), prev, "hizb/rub must be non-decreasing in ayah order")
            self.assertEqual(hizb, (rub + 3) // 4, "every hizb holds exactly 4 rub quarters")
            prev = (hizb, rub)

    def test_sajdah_positions(self):
        conn = self._build()
        cur = conn.cursor()
        count = cur.execute("SELECT COUNT(*) FROM ayah WHERE sajdah = 1").fetchone()[0]
        self.assertEqual(count, 15, "Madinah mushaf convention: 15 sajdah positions")
        # First sajdah (Tanzil): Al-A'raf 7:206
        row = cur.execute(
            "SELECT sajdah FROM ayah WHERE surah_id = 7 AND ayah_number = 206"
        ).fetchone()
        self.assertEqual(row[0], 1)

    def test_spot_check_juz_and_page_boundaries(self):
        conn = self._build()
        cur = conn.cursor()
        # Juz 2 starts at Al-Baqarah 2:142 (Tanzil markers)
        self.assertEqual(
            cur.execute("SELECT juz FROM ayah WHERE surah_id=2 AND ayah_number=142").fetchone()[0], 2)
        self.assertEqual(
            cur.execute("SELECT juz FROM ayah WHERE surah_id=2 AND ayah_number=141").fetchone()[0], 1)
        # Juz 30 starts at An-Naba 78:1
        self.assertEqual(
            cur.execute("SELECT juz FROM ayah WHERE surah_id=78 AND ayah_number=1").fetchone()[0], 30)
        # Page 2 starts at Al-Baqarah 2:1
        self.assertEqual(
            cur.execute("SELECT page FROM ayah WHERE surah_id=2 AND ayah_number=1").fetchone()[0], 2)
        # First ayah: page 1, hizb 1, rub 1
        self.assertEqual(
            cur.execute("SELECT page, hizb, rub FROM ayah WHERE surah_id=1 AND ayah_number=1").fetchone(),
            (1, 1, 1))

    def test_uthmani_line_count_validated(self):
        with open(self.uthmani, "a", encoding="utf-8") as f:
            f.write("سطر زائد\n")
        with self.assertRaises(ValueError):
            bq.init_database(self.db)


if __name__ == "__main__":
    unittest.main()
