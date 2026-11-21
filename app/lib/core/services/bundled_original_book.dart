import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Reads a pinned original book from installation assets, never the network.
/// Payload inclusion and default UI wiring remain separate release decisions.
class BundledOriginalBook {
  final String assetPath, compressedSha256, originalSha256;
  final int originalBytes;
  final Future<Uint8List> Function(String) readAsset;
  Future<String>? _loading;
  BundledOriginalBook({required this.assetPath, required this.compressedSha256,
    required this.originalSha256, required this.originalBytes,
    Future<Uint8List> Function(String)? readAsset})
      : readAsset=readAsset??_readAsset;
  static Future<Uint8List> _readAsset(String path) async {
    final bytes=await rootBundle.load(path);
    return bytes.buffer.asUint8List(bytes.offsetInBytes,bytes.lengthInBytes);
  }
  Future<String> load() => _loading ??= _load().catchError((Object error) {
    _loading=null;
    throw error;
  });
  Future<String> _load() async {
    final packed=await readAsset(assetPath);
    if(sha256.convert(packed).toString()!=compressedSha256) {
      throw const FormatException('Bundled book compressed checksum mismatch');
    }
    final bytes=GZipDecoder().decodeBytes(packed);
    if(bytes.length!=originalBytes || sha256.convert(bytes).toString()!=originalSha256) {
      throw const FormatException('Bundled book original checksum mismatch');
    }
    return utf8.decode(bytes);
  }
}
