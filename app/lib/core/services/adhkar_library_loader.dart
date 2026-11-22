import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import '../models/adhkar_library.dart';

/// Loads only the pinned bundled text. This never reads or writes user progress.
class AdhkarLibraryLoader {
  static const assetPath = 'assets/data/rn0x_adhkar.json';

  static Future<ImportedAdhkarLibrary> load({AssetBundle? bundle}) async {
    final bytes = await (bundle ?? rootBundle).load(assetPath);
    final source =
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    if (sha256.convert(source).toString() !=
        ImportedAdhkarLibrary.bundledSha256) {
      throw const FormatException(
          'Bundled Adhkar source integrity check failed');
    }
    return ImportedAdhkarLibrary.parse(utf8.decode(source));
  }
}
