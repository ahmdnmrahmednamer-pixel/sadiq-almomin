class Ayah {
  final int id;
  final int surahId;
  final int ayahNumber;
  final int juz;
  final int hizb;
  final int rub;
  final int page;
  final int sajdah;
  final String textUthmani;
  final String textImlaei;
  final String textSearch;
  final String? tafseer;

  const Ayah({
    required this.id,
    required this.surahId,
    required this.ayahNumber,
    required this.juz,
    required this.hizb,
    required this.rub,
    required this.page,
    required this.sajdah,
    required this.textUthmani,
    required this.textImlaei,
    required this.textSearch,
    this.tafseer,
  });

  factory Ayah.fromRow(Map<String, dynamic> row) {
    return Ayah(
      id: row['id'] as int,
      surahId: (row['surah_id'] ?? row['surahId']) as int,
      ayahNumber: (row['ayah_number'] ?? row['ayahNumber']) as int,
      juz: row['juz'] as int,
      hizb: row['hizb'] as int? ?? 1,
      rub: row['rub'] as int? ?? 1,
      page: row['page'] as int,
      sajdah: row['sajdah'] as int? ?? 0,
      textUthmani: (row['text_uthmani'] ?? row['textUthmani']) as String,
      textImlaei: (row['text_imlaei'] ?? row['textImlaei']) as String? ?? '',
      textSearch: (row['text_search'] ?? row['textSearch']) as String? ?? '',
      tafseer: row['tafseer'] as String?,
    );
  }

    bool get hasSajdah => sajdah > 0;

  /// Returns the Uthmani text of the Ayah without the prefixed Basmalah
  /// in Ayah 1 of all surahs (Surahs 2-114, except Surah 9 which has no Basmalah).
  /// Surah 1 (Al-Fatihah) keeps its Basmalah as it is Ayah 1 by consensus.
  String get cleanTextUthmani {
    if (surahId != 1 && ayahNumber == 1) {
      const basmalaPrefixes = [
        'بِسۡمِ ٱللَّهِ ٱلرَّحۡمَـٰنِ ٱلرَّحِیمِ ',
        'بِّسۡمِ ٱللَّهِ ٱلرَّحۡمَـٰنِ ٱلرَّحِیمِ ',
        'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ ',
        'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ ',
        'بِسۡمِ ٱللَّهِ ٱلرَّحۡمَـٰنِ ٱلرَّحِیمِ',
        'بِّسۡمِ ٱللَّهِ ٱلرَّحۡمَـٰنِ ٱلرَّحِیمِ',
        'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
        'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ',
      ];
      for (final prefix in basmalaPrefixes) {
        if (textUthmani.startsWith(prefix)) {
          return textUthmani.substring(prefix.length).trim();
        }
      }
    }
    return textUthmani;
  }

  /// Returns the Imlaei text without the prefixed Basmalah
  String get cleanTextImlaei {
    if (surahId != 1 && ayahNumber == 1) {
      const basmalaPrefixes = [
        'بسم الله الرحمن الرحيم ',
        'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ ',
        'بِسۡمِ ٱللَّهِ ٱلرَّحۡمَـٰنِ ٱلرَّحِیمِ ',
        'بسم الله الرحمن الرحيم',
        'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ',
      ];
      for (final prefix in basmalaPrefixes) {
        if (textImlaei.startsWith(prefix)) {
          return textImlaei.substring(prefix.length).trim();
        }
      }
    }
    return textImlaei;
  }
}
