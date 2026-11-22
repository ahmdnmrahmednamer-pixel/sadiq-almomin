import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../audio/islamic_audio_models.dart';

/// Cache eligibility is tied to the exact snapshot that passed validation.
bool sameAudioFileSnapshot(FileStat a, FileStat b) =>
    a.type == FileSystemEntityType.file &&
    b.type == FileSystemEntityType.file &&
    a.size == b.size &&
    a.modified == b.modified &&
    a.changed == b.changed;

Stream<List<int>> _gitBlobBytes(File file, int size) async* {
  yield utf8.encode('blob $size\u0000');
  yield* file.openRead();
}

/// Legacy records retain their existing minimum-size rule. Pinned records must
/// also match the source's exact byte count and Git blob SHA-1. This verifies
/// source bytes, not voice identity, audio quality or reuse rights.
Future<FileStat?> validatedAudioFileStat(
    IslamicAudioTrack track, File file) async {
  try {
    final before = file.statSync();
    if (before.type != FileSystemEntityType.file || before.size <= 1000) {
      return null;
    }
    final expected = track.remoteGitBlobSha1;
    if (expected == null) return before;
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(expected) ||
        track.fileSizeBytes == null ||
        before.size != track.fileSizeBytes) {
      return null;
    }
    final digest = await sha1.bind(_gitBlobBytes(file, before.size)).single;
    final after = file.statSync();
    if (digest.toString() != expected ||
        !sameAudioFileSnapshot(before, after)) {
      return null;
    }
    return after;
  } on FileSystemException {
    return null;
  }
}
