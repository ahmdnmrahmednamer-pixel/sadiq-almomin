import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/audio/islamic_audio_models.dart';
import 'package:almomin/core/services/islamic_audio_file_integrity.dart';

void main() {
  late Directory dir;
  late File file;
  final data = List<int>.generate(4096, (i) => i % 251);
  String blob(List<int> bytes) => sha1.convert(
      [...utf8.encode('blob ${bytes.length}\u0000'), ...bytes]).toString();
  IslamicAudioTrack track({String? hash, int? size}) => IslamicAudioTrack(
      id: 'fixture',
      title: 'fixture',
      subtitle: '',
      type: IslamicAudioType.adhan,
      durationFormatted: '',
      remoteGitBlobSha1: hash,
      fileSizeBytes: size);
  setUp(() {
    dir = Directory.systemTemp.createTempSync('pinned-integrity-');
    file = File('${dir.path}/audio.mp3')..writeAsBytesSync(data);
  });
  tearDown(() => dir.deleteSync(recursive: true));
  test('exact pinned Git blob and size are accepted', () async {
    final stat = await validatedAudioFileStat(
        track(hash: blob(data), size: data.length), file);
    expect(stat, isNotNull);
    expect(sameAudioFileSnapshot(stat!, file.statSync()), isTrue);
  });
  test('plain content SHA1 is not a Git blob digest', () async {
    expect(
        await validatedAudioFileStat(
            track(hash: sha1.convert(data).toString(), size: data.length),
            file),
        isNull);
  });
  test('same-sized substituted bytes fail without deleting the file', () async {
    file.writeAsBytesSync(List.filled(data.length, 0));
    expect(
        await validatedAudioFileStat(
            track(hash: blob(data), size: data.length), file),
        isNull);
    expect(file.lengthSync(), data.length);
  });
  test('truncated or extended bytes fail the exact size check', () async {
    for (final size in [data.length - 1, data.length + 1]) {
      expect(
          await validatedAudioFileStat(
              track(hash: blob(data), size: size), file),
          isNull);
    }
  });
  test('pinned metadata fails closed if digest or size is invalid', () async {
    for (final hash in ['bad', blob(data).toUpperCase()]) {
      expect(
          await validatedAudioFileStat(
              track(hash: hash, size: data.length), file),
          isNull);
    }
    expect(await validatedAudioFileStat(track(hash: blob(data)), file), isNull);
  });
  test('legacy tracks retain the minimum-size rule, not a new exact-size rule',
      () async {
    expect(await validatedAudioFileStat(track(size: 999999), file), isNotNull);
    file.writeAsBytesSync(List.filled(1000, 0));
    expect(await validatedAudioFileStat(track(), file), isNull);
  });
  test('missing files fail closed', () async {
    file.deleteSync();
    expect(
        await validatedAudioFileStat(
            track(hash: blob(data), size: data.length), file),
        isNull);
  });
}
