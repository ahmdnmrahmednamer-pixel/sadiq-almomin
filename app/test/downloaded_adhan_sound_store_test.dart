import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almomin/core/audio/islamic_audio_catalog.dart';
import 'package:almomin/core/audio/islamic_audio_models.dart';
import 'package:almomin/core/services/downloaded_adhan_sound_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fixture/downloaded_adhan_sound');
  final bytes = List<int>.generate(4096, (i) => i % 251);
  final hash = sha1.convert([
    ...utf8.encode('blob ${bytes.length}\u0000'),
    ...bytes,
  ]).toString();
  final id = 'kiwifu_adhan_$hash';
  final uri =
      'content://${DownloadedAdhanSoundStore.authority}/v1/$hash/${bytes.length}';
  late Directory root;
  late File file;
  late DownloadedAdhanSoundStore store;
  late Map<String, dynamic> answer;
  var nativeCalls = 0;
  Future<void> Function()? duringNative;
  Object? nativeError;
  var nativeNull = false;
  Map<String, dynamic>? arguments;

  IslamicAudioTrack track(
          {String? trackId, int? size, IslamicAudioType? type}) =>
      IslamicAudioTrack(
          id: trackId ?? id,
          title: 'fixture',
          subtitle: '',
          type: type ?? IslamicAudioType.adhan,
          durationFormatted: '',
          remoteGitBlobSha1: hash,
          fileSizeBytes: size ?? bytes.length);

  DownloadedAdhanSoundStore make(
          {List<IslamicAudioTrack>? catalog,
          bool android = true,
          Duration timeout = const Duration(seconds: 20)}) =>
      DownloadedAdhanSoundStore.forTesting(
          channel: channel,
          catalog: catalog ?? [track()],
          audioDirectory: () async => root,
          androidAvailable: android,
          nativeTimeout: timeout);

  setUp(() {
    root = Directory.systemTemp.createTempSync('native-adhan-uri-');
    file = File('${root.path}/$id.mp3')..writeAsBytesSync(bytes);
    nativeCalls = 0;
    duringNative = null;
    nativeError = null;
    nativeNull = false;
    arguments = null;
    answer = {'uri': uri, 'blobSha1': hash, 'sizeBytes': bytes.length};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'prepare');
      nativeCalls++;
      arguments = Map<String, dynamic>.from(call.arguments as Map);
      if (duringNative != null) await duringNative!();
      if (nativeError != null) throw nativeError!;
      return nativeNull ? null : answer;
    });
    store = make();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    root.deleteSync(recursive: true);
  });

  test(
      'canonical source bytes produce one stable private URI and distinct channel',
      () async {
    final sound = await store.prepare(id);
    expect(sound.uri, uri);
    expect(sound.blobSha1, hash);
    expect(sound.channelId, 'prayer_downloaded_adhan_v1_$hash');
    expect(arguments, {'blobSha1': hash, 'sizeBytes': bytes.length});
    expect(nativeCalls, 1);
  });
  test('unknown IDs never reach native code', () async {
    await expectLater(store.prepare('unknown'), throwsStateError);
    expect(nativeCalls, 0);
  });
  test('a non-digest-named record cannot opt into this native provider',
      () async {
    store = make(catalog: [track(trackId: 'legacy')]);
    await expectLater(store.prepare('legacy'), throwsStateError);
    expect(nativeCalls, 0);
  });
  test('another recording type cannot masquerade as an adhan', () async {
    store = make(catalog: [track(type: IslamicAudioType.iqamah)]);
    await expectLater(store.prepare(id), throwsStateError);
    expect(nativeCalls, 0);
  });
  test('duplicate canonical IDs are rejected', () async {
    store = make(catalog: [track(), track()]);
    await expectLater(store.prepare(id), throwsStateError);
    expect(nativeCalls, 0);
  });
  test('the fixture catalog is snapshotted', () async {
    final catalog = [track()];
    store = make(catalog: catalog);
    catalog.clear();
    expect((await store.prepare(id)).uri, uri);
  });
  test('missing download is rejected before any URI grant request', () async {
    file.deleteSync();
    await expectLater(store.prepare(id), throwsStateError);
    expect(nativeCalls, 0);
  });
  test('same-sized corrupt download is rejected before native code', () async {
    file.writeAsBytesSync(List.filled(bytes.length, 7));
    await expectLater(store.prepare(id), throwsStateError);
    expect(nativeCalls, 0);
  });
  test('wrong catalog length is not inferred from a local file', () async {
    store = make(catalog: [track(size: bytes.length + 1)]);
    await expectLater(store.prepare(id), throwsStateError);
    expect(nativeCalls, 0);
  });
  test('another platform cannot claim Android preparation', () async {
    store = make(android: false);
    await expectLater(store.prepare(id), throwsUnsupportedError);
    expect(nativeCalls, 0);
  });
  for (final entry in {
    'another authority': 'content://other.invalid/v1/$hash/${bytes.length}',
    'filesystem URI': 'file:///private/recording.mp3',
    'extra query': '$uri?ignored=1',
    'wrong path': '$uri/other',
  }.entries) {
    test('native response rejects ${entry.key}', () async {
      answer['uri'] = entry.value;
      await expectLater(store.prepare(id), throwsStateError);
    });
  }
  test('native response must confirm the exact blob identity', () async {
    answer['blobSha1'] = 'a' * 40;
    await expectLater(store.prepare(id), throwsStateError);
  });
  test('a null native confirmation is rejected', () async {
    nativeNull = true;
    await expectLater(store.prepare(id), throwsStateError);
  });
  test('a noninteger native byte count is rejected', () async {
    answer['sizeBytes'] = bytes.length.toDouble();
    await expectLater(store.prepare(id), throwsStateError);
  });
  test('native response must confirm the exact byte count', () async {
    answer['sizeBytes'] = bytes.length + 1;
    await expectLater(store.prepare(id), throwsStateError);
  });
  test('mutation while native preparation is pending is rejected', () async {
    duringNative =
        () async => file.writeAsBytesSync(List.filled(bytes.length, 9));
    await expectLater(store.prepare(id), throwsStateError);
  });
  test('deletion while native preparation is pending is rejected', () async {
    duringNative = () async {
      file.deleteSync();
    };
    await expectLater(store.prepare(id), throwsA(anything));
  });
  test('native refusal is not replaced with a bundled/default URI', () async {
    nativeError = PlatformException(code: 'recording_unavailable');
    await expectLater(store.prepare(id), throwsA(isA<PlatformException>()));
  });
  test('a prior success never bypasses fresh native validation', () async {
    await store.prepare(id);
    nativeError = PlatformException(code: 'recording_unavailable');
    await expectLater(store.prepare(id), throwsA(isA<PlatformException>()));
    expect(nativeCalls, 2);
  });
  test('a timed-out native request does not publish preparation', () async {
    store = make(timeout: const Duration(milliseconds: 10));
    final blocked = Completer<void>();
    duringNative = () => blocked.future;
    await expectLater(store.prepare(id), throwsA(isA<TimeoutException>()));
    blocked.complete();
    await Future<void>.delayed(Duration.zero);
  });
  test('current pinned catalog fits the exact native file contract', () {
    final pinned =
        islamicAudioCatalog.where((track) => track.remoteGitBlobSha1 != null);
    expect(pinned, hasLength(230));
    expect(pinned.every(DownloadedAdhanSoundStore.isPinnedAdhanTrack), isTrue);
    expect(
        pinned.every(
            (track) => DownloadedAdhanSoundStore.isPinnedAdhanId(track.id)),
        isTrue);
    expect(DownloadedAdhanSoundStore.isPinnedAdhanId('adhan_makkah'), isFalse);
  });
}
