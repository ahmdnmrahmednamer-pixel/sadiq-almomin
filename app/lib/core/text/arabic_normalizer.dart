/// Arabic Search Normalization (Appendix A Reference Algorithm)
/// Matches normalizer.py and normalizer_vectors.json test vectors.
library;

class ArabicNormalizer {
  // Tashkeel, Quranic recitation signs, tatweel, and ayah markers
  static final RegExp diacriticsRegex = RegExp(
    r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u08D3-\u08FF\u0640\u06DD]',
  );

  static final Map<String, String> digitMap = {
    '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
    '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
    '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
    '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
  };

  static final Map<String, String> looseLetterMap = {
    'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا',
    'ى': 'ي',
    'ؤ': 'و', 'ئ': 'ي',
    'ة': 'ه',
    'ی': 'ي', 'ک': 'ك',
  };

  /// Normalizes Arabic text for searching and indexing.
  /// Never mutates canonical Quran text.
  static String normalize(String text, {bool loose = true}) {
    if (text.isEmpty) return '';

    // 1. Remove diacritics and recitation signs
    String cleaned = text.replaceAll(diacriticsRegex, '');

    // 2. Normalize letter variants
    StringBuffer sb = StringBuffer();
    for (int i = 0; i < cleaned.length; i++) {
      String char = cleaned[i];
      if (loose && looseLetterMap.containsKey(char)) {
        sb.write(looseLetterMap[char]);
      } else if (digitMap.containsKey(char)) {
        sb.write(digitMap[char]);
      } else {
        sb.write(char);
      }
    }

    // 3. Collapse whitespace and trim
    return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Normalizes Arabic-Indic (٠-٩) and Eastern Arabic/Urdu (۰-۹) digits to ASCII (0-9)
  static String normalizeDigits(String input) {
    if (input.isEmpty) return '';
    final sb = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final ch = input[i];
      if (digitMap.containsKey(ch)) {
        sb.write(digitMap[ch]);
      } else if (ch == '٫') {
        sb.write('.');
      } else if (ch == '،' || ch == ',' || ch == '٬') {
        // strip thousand separators
      } else {
        sb.write(ch);
      }
    }
    return sb.toString().trim();
  }

  /// Safely parses an integer from user input containing ASCII, Arabic-Indic, or Urdu digits
  static int? tryParseInt(String input) {
    final cleaned = normalizeDigits(input);
    if (cleaned.isEmpty) return null;
    return int.tryParse(cleaned);
  }

  /// Safely parses a double from user input containing ASCII, Arabic-Indic, or Urdu digits
  static double? tryParseDouble(String input) {
    final cleaned = normalizeDigits(input);
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  // =========================================================================
  // Search-Only Uthmani-to-Imlaei Canonicalizer
  // Never mutates canonical displayed Quran text and leaves normalize() intact.
  // =========================================================================
  static final RegExp _searchSpacersAndMarks = RegExp(
    r'[\u200A\u2060\u0640\u06DD\u06DE\u06E9]',
  );
  static final RegExp _searchDiacriticsKeepDaggerAndSmallYeh = RegExp(
    r'[\u0610-\u061A\u064B-\u065F\u06D6-\u06E6\u06E8-\u06ED\u08D3-\u08FF]',
  );
  static final List<(RegExp, String Function(Match))> _imlaeiDefectiveFixes = [
    (
      RegExp(r'(^|\s)(و|ف|ب|ل|ك)?ذالك(م|ما|ن)?(?=\s|$)'),
      (m) => '${m.group(1) ?? ''}${m.group(2) ?? ''}ذلك${m.group(3) ?? ''}',
    ),
    (
      RegExp(r'(^|\s)(و|ف|ب|ل|ك)?هاذا(?=\s|$)'),
      (m) => '${m.group(1) ?? ''}${m.group(2) ?? ''}هذا',
    ),
    (
      RegExp(r'(^|\s)(و|ف|ب|ل|ك)?هاذه(?=\s|$)'),
      (m) => '${m.group(1) ?? ''}${m.group(2) ?? ''}هذه',
    ),
    (
      RegExp(r'(^|\s)(و|ف|ب|ل|ك)?هاذان(?=\s|$)'),
      (m) => '${m.group(1) ?? ''}${m.group(2) ?? ''}هذان',
    ),
    (
      RegExp(r'(^|\s)(و|ف|ب|ل|ك)?هاولاء(?=\s|$)'),
      (m) => '${m.group(1) ?? ''}${m.group(2) ?? ''}هولاء',
    ),
    (
      RegExp(r'(^|\s)(و|ف|ل)?لاكن(ا|ه|هم|كم|نا|ي)?(?=\s|$)'),
      (m) => '${m.group(1) ?? ''}${m.group(2) ?? ''}لكن${m.group(3) ?? ''}',
    ),
    (
      RegExp(r'(^|\s)(و|ب|ل|ف)?الرحمان(?=\s|$)'),
      (m) => '${m.group(1) ?? ''}${m.group(2) ?? ''}الرحمن',
    ),
    (
      RegExp(r'(^|\s)(و|ف|ب|ل)?رحمان(?=\s|$)'),
      (m) => '${m.group(1) ?? ''}${m.group(2) ?? ''}رحمن',
    ),
    (
      RegExp(r'(^|\s)(و|ف|ب|ل)?الاه(ا|ك|كم|نا|هم|ي|ين|ه)?(?=\s|$)'),
      (m) => '${m.group(1) ?? ''}${m.group(2) ?? ''}اله${m.group(3) ?? ''}',
    ),
    (
      RegExp(r'(^|\s)(و|ف|ب|ل)?اولاءك(?=\s|$)'),
      (m) => '${m.group(1) ?? ''}${m.group(2) ?? ''}اوليك',
    ),
    (
      RegExp(r'(^|\s)(و|ف|ب|ل)?اولائك(?=\s|$)'),
      (m) => '${m.group(1) ?? ''}${m.group(2) ?? ''}اوليك',
    ),
    (
      RegExp(r'(^|\s)(و|ف|ب|ل)?السموات(?=\s|$)'),
      (m) => '${m.group(1) ?? ''}${m.group(2) ?? ''}السماوات',
    ),
    (
      RegExp(r'(^|\s)(و|ف|ب|ل)?سموات(?=\s|$)'),
      (m) => '${m.group(1) ?? ''}${m.group(2) ?? ''}سماوات',
    ),
    (
      RegExp(r'(^|\s)ياايها(?=\s|$)'),
      (m) => '${m.group(1) ?? ''}يا ايها',
    ),
    (
      RegExp(r'(^|\s)يايها(?=\s|$)'),
      (m) => '${m.group(1) ?? ''}يا ايها',
    ),
  ];

  /// Search-only normalization aligning Uthmani script orthography (invisible
  /// hair-space/word-joiner splitters, dagger alif, waw+dagger alif, standalone
  /// hamza-alif, small high yeh, and classical defective-alif words) with
  /// standard Arabic Imlaei search queries.
  static String normalizeForQuranSearch(String text) {
    if (text.isEmpty) return '';

    String cleaned = text
        .replaceAll(_searchSpacersAndMarks, '')
        .replaceAll(_searchDiacriticsKeepDaggerAndSmallYeh, '')
        .replaceAll('ى\u0670', 'ي')
        .replaceAll('ی\u0670', 'ي')
        .replaceAll('و\u0670ة', 'اة')
        .replaceAll('و\u0670ا', 'ا')
        .replaceAll('\u0670', 'ا')
        .replaceAll('\u06E7', 'ي');

    final sb = StringBuffer();
    for (int i = 0; i < cleaned.length; i++) {
      final char = cleaned[i];
      if (looseLetterMap.containsKey(char)) {
        sb.write(looseLetterMap[char]);
      } else if (digitMap.containsKey(char)) {
        sb.write(digitMap[char]);
      } else {
        sb.write(char);
      }
    }

    String result = sb
        .toString()
        .replaceAll('ءا', 'ا')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    for (final fix in _imlaeiDefectiveFixes) {
      result = result.replaceAllMapped(fix.$1, fix.$2);
    }

    return result.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
