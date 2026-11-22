import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../audio/islamic_audio_catalog.dart';
import '../audio/islamic_audio_models.dart';
import 'islamic_audio_file_integrity.dart';

@immutable
class PreparedDownloadedAdhan {
  final String uri;
  final String blobSha1;
  final int sizeBytes;
  const PreparedDownloadedAdhan({
    required this.uri,
    required this.blobSha1,
    required this.sizeBytes,
  });

  // Android channel sounds are immutable. Never reuse a bundled voice channel.
  String get channelId => 'prayer_downloaded_adhan_v1_$blobSha1';
}

/// This prepares a sound URI only. It never saves a voice or changes an alarm.
class DownloadedAdhanSoundStore {
  static final instance = DownloadedAdhanSoundStore._(
    channel: const MethodChannel('almomin/downloaded_adhan_sound'),
    catalog: islamicAudioCatalog,
    audioDirectory: _defaultDirectory,
    androidAvailable:
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
    nativeTimeout: const Duration(seconds: 20),
  );

  DownloadedAdhanSoundStore._({
    required MethodChannel channel,
    required List<IslamicAudioTrack> catalog,
    required Future<Directory> Function() audioDirectory,
    required bool androidAvailable,
    required Duration nativeTimeout,
  })  : _channel = channel,
        _catalog = List.unmodifiable(catalog),
        _audioDirectory = audioDirectory,
        _androidAvailable = androidAvailable,
        _nativeTimeout = nativeTimeout;

  @visibleForTesting
  DownloadedAdhanSoundStore.forTesting({
    required MethodChannel channel,
    required List<IslamicAudioTrack> catalog,
    required Future<Directory> Function() audioDirectory,
    bool androidAvailable = true,
    Duration nativeTimeout = const Duration(seconds: 20),
  }) : this._(
            channel: channel,
            catalog: catalog,
            audioDirectory: audioDirectory,
            androidAvailable: androidAvailable,
            nativeTimeout: nativeTimeout);

  static bool get platformSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static const authority = 'org.almomin.app.downloaded_adhan_audio';
  static const maxBytes = 100 * 1024 * 1024;
  final MethodChannel _channel;
  final List<IslamicAudioTrack> _catalog;
  final Future<Directory> Function() _audioDirectory;
  final bool _androidAvailable;
  final Duration _nativeTimeout;

  static Future<Directory> _defaultDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    return Directory('${root.path}/adhkar_audio');
  }

  static bool isPinnedAdhanTrack(IslamicAudioTrack track) {
    final hash = track.remoteGitBlobSha1;
    final size = track.fileSizeBytes;
    return track.type == IslamicAudioType.adhan &&
        hash != null &&
        RegExp(r'^[0-9a-f]{40}$').hasMatch(hash) &&
        track.id == 'kiwifu_adhan_$hash' &&
        size != null &&
        size > 1000 &&
        size <= maxBytes;
  }

  static bool isPinnedAdhanId(String id) => islamicAudioCatalog
      .any((track) => track.id == id && isPinnedAdhanTrack(track));

  Future<PreparedDownloadedAdhan> prepare(String id) async {
    if (!_androidAvailable) {
      throw UnsupportedError('Native Android sound is unavailable');
    }
    final matches = _catalog.where((track) => track.id == id);
    if (matches.length != 1 || !isPinnedAdhanTrack(matches.single)) {
      throw StateError(
          'This recording has no supported pinned native identity');
    }
    final track = matches.single;
    final directory = await _audioDirectory();
    final file = File('${directory.path}/$id.mp3');
    final checked = await validatedAudioFileStat(track, file);
    if (checked == null) {
      throw StateError('Download this recording again before assigning it');
    }
    final hash = track.remoteGitBlobSha1!;
    final size = track.fileSizeBytes!;
    final expectedUri = Uri(
      scheme: 'content',
      host: authority,
      pathSegments: ['v1', hash, size.toString()],
    ).toString();
    final response =
        await _channel.invokeMapMethod<String, dynamic>('prepare', {
      'blobSha1': hash,
      'sizeBytes': size,
    }).timeout(_nativeTimeout);
    // Timestamp snapshots can collide for fast same-sized rewrites. Re-hash
    // after the asynchronous native handshake, not only before it.
    final confirmed = await validatedAudioFileStat(track, file);
    if (response == null ||
        response['uri'] != expectedUri ||
        response['blobSha1'] != hash ||
        response['sizeBytes'] is! int ||
        response['sizeBytes'] != size ||
        confirmed == null ||
        !sameAudioFileSnapshot(checked, confirmed) ||
        !sameAudioFileSnapshot(confirmed, file.statSync())) {
      throw StateError(
          'Native sound preparation did not confirm the recording');
    }
    final sound = PreparedDownloadedAdhan(
        uri: expectedUri, blobSha1: hash, sizeBytes: size);
    return sound;
  }
}
