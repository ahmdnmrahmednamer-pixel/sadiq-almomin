import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import '../lib/core/services/shamela_library_service.dart';
import '../lib/core/services/shamela_epub_service.dart';

void main() {
  test('LIVE official download and internal complete-book offline reopening',
      () async {
    final root = await Directory.systemTemp.createTemp('shamela-live-test-');
    final dio = Dio();
    final svc = ShamelaEpubService(dio: dio, rootDir: root);
    const expected = ShamelaBook(
        id: 1446,
        title: 'صحيح ابن خزيمة',
        author: 'ابن خزيمة',
        downloadUrl: '',
        urlCandidates: []);
    final downloaded = await svc.downloadBook(expected);
    expect(downloaded.id, 1446);
    expect(downloaded.pages.length, 5118);
    expect(downloaded.flattenedToc.length, 2245);
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(DioException.connectionError(
          requestOptions: options,
          reason: 'NETWORK DISABLED FOR OFFLINE VERIFICATION'));
    }));
    final restored = await svc.loadSavedBook(1446);
    expect(restored, isNotNull);
    expect(restored!.pages.length, 5118);
    expect(restored.pages[1].text, downloaded.pages[1].text);
    expect(restored.pages.last.text, downloaded.pages.last.text);
    expect(restored.flattenedToc.length, 2245);
    final output = File('/tmp/shamela-live-verification.txt');
    await output.writeAsString(
        'Official source: ${restored.sourceUrl}\nBook: ${restored.id} ${restored.title}\nSpine pages: ${restored.pages.length}\nTOC entries: ${restored.flattenedToc.length}\nFirst and last page read after network disabled: PASS\nStorage: ${root.path}/shamela/1446\n');
  },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: Platform.environment['SHAMELA_LIVE'] != '1');
}
