import unittest
from index_explicit_verse_quotes import build_index

SURAH=[{'number':2,'name':'سورة اختبار','ayahs':[
 {'numberInSurah':1,'text':'اول نص تجريبي للربط'},
 {'numberInSurah':2,'text':'نص يتكرر هنا ثم نهاية'},
 {'numberInSurah':3,'text':'نص يتكرر هنا ومرة اخرى'}]}]
class IndexTest(unittest.TestCase):
 def test_unique_keeps_source_span_and_printed_page(self):
  s='سورة اختبار\nقوله تعالى اول نص تجريبي الآية أخرج مصدر تجريبي\nالجزء: 1 ¦ الصفحة: 9\n'
  d=build_index(s,SURAH);r=d['records'][0]
  self.assertEqual(r['candidates'],[1]);self.assertEqual(r['page'],9)
  self.assertEqual(s[r['start']:r['end']].splitlines()[0],'قوله تعالى اول نص تجريبي الآية أخرج مصدر تجريبي')
  self.assertFalse(d['reviewed'])
 def test_ambiguous_does_not_select_first_match(self):
  r=build_index('سورة اختبار\nقوله تعالى نص يتكرر هنا الآية أخرج خبر',SURAH)['records'][0]
  self.assertEqual(r['status'],'ambiguous');self.assertEqual(r['candidates'],[2,3])
 def test_unknown_chapter_does_not_inherit_previous_surah(self):
  r=build_index('سورة اخرى\nقوله تعالى اول نص تجريبي الآية أخرج خبر',SURAH)['records'][0]
  self.assertIsNone(r['surah']);self.assertEqual(r['status'],'unmatched')
 def test_short_quote_stays_unmatched(self):
  r=build_index('سورة اختبار\nقوله تعالى اول نص الآية أخرج خبر',SURAH)['records'][0]
  self.assertEqual(r['status'],'unmatched')
 def test_narrative_quote_is_not_used_to_pick_verse(self):
  r=build_index('سورة اختبار\nقوله تعالى غير مطابق هنا الآية أخرج اول نص تجريبي',SURAH)['records'][0]
  self.assertEqual(r['status'],'unmatched')
if __name__=='__main__':unittest.main()
