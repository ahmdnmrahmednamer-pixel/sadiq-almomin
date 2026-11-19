import 'package:dio/dio.dart';

/// A verbatim source response. Provider and book IDs are not inferred from text.
class VerseSourceText {
  final String providerId, bookId, text, sourceUrl;
  final int surah, firstAyah, lastAyah;
  const VerseSourceText({required this.providerId, required this.bookId,
    required this.text, required this.sourceUrl, required this.surah,
    required this.firstAyah, required this.lastAyah});
  bool contains(int surahId, int ayah) => surah == surahId &&
    ayah >= firstAyah && ayah <= lastAyah;
}

/// Technical connector only. Catalogue approval and display permissions remain
/// separate from transport. No bundled corpus and no persistent text cache.
class AlQuranCloudTafsirClient {
  final Dio dio;
  AlQuranCloudTafsirClient({Dio? dio}) : dio = dio ?? Dio(BaseOptions(
    baseUrl:'https://api.alquran.cloud/v1',
    connectTimeout:const Duration(seconds:10), receiveTimeout:const Duration(seconds:20)));
  Future<VerseSourceText> fetch({required String editionId,
    required int surah, required int ayah}) async {
    if (!RegExp(r'^ar\.[a-z_]+$').hasMatch(editionId) || surah < 1 || surah > 114 || ayah < 1) {
      throw ArgumentError('Invalid source identity');
    }
    final response = await dio.get('/ayah/$surah:$ayah/$editionId');
    final root = response.data;
    if (root is! Map || root['code'] != 200 || root['data'] is! Map) {
      throw const FormatException('Invalid source response');
    }
    final data = root['data'] as Map;
    final edition = data['edition'];
    final chapter = data['surah'];
    final text = data['text'];
    if (edition is! Map || edition['identifier'] != editionId ||
      edition['type'] != 'tafsir' || chapter is! Map || chapter['number'] != surah ||
      data['numberInSurah'] != ayah || text is! String || text.trim().isEmpty) {
      throw const FormatException('Source identity or verse mismatch');
    }
    return VerseSourceText(providerId:'alquran.cloud',bookId:editionId,
      text:text,sourceUrl:response.realUri.toString(),surah:surah,
      firstAyah:ayah,lastAyah:ayah);
  }
}
