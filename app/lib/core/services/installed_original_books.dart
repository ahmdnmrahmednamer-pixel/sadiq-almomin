import 'bundled_original_book.dart';

// Exact pinned installation books. Missing or changed assets fail closed.
class InstalledOriginalBooks {
  static BundledOriginalBook jadwal() => BundledOriginalBook(
    assetPath: 'assets/data/jadwal-original.gz',
    compressedSha256: '58b97623d0bd667b67e6d5f9b93c5ca586a50813b5bdae1da792f7a78e5b778a',
    originalSha256: 'df86efc29efbf82f6683951fb2fd2e94220e5102f1209d1e0543055b85380ba0',
    originalBytes: 14839759,
  );
  static BundledOriginalBook budur() => BundledOriginalBook(
    assetPath: 'assets/data/budur-original.gz',
    compressedSha256: '150073b2aa55748ba5fae2a36dcb9478bd6eaa846e2786b0c53936aa6f947354',
    originalSha256: '6012b24bcaccd17ba4d3f1e9828c69c0be86cc2b1a38f41a491ea116885d6bb2',
    originalBytes: 1043729,
  );
}
