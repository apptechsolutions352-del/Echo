import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:metadata_god/metadata_god.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../data/library_database.dart';
import '../models/track.dart';

class LibraryScanner {
  LibraryScanner(this._database);

  static const _extensions = {
    '.mp3',
    '.flac',
    '.ogg',
    '.oga',
    '.m4a',
    '.aac',
    '.wav',
    '.opus',
    '.wma',
  };

  final LibraryDatabase _database;
  final Map<String, StreamSubscription<WatchEvent>> _watchSubscriptions = {};
  final StreamController<String> _events = StreamController<String>.broadcast();
  Stream<String> get events => _events.stream;

  static bool supportsAudioPath(String path) =>
      _extensions.contains(p.extension(path).toLowerCase());

  Future<int> scanRoot(
    String root, {
    void Function(int visited, int imported)? onProgress,
  }) async {
    final directory = Directory(root);
    if (!await directory.exists()) {
      throw FileSystemException('Music folder does not exist', root);
    }
    final rootPath = p.normalize(directory.absolute.path);
    await _database.addRoot(rootPath);
    var visited = 0;
    var imported = 0;
    final seenPaths = <String>{};
    final pending = <TrackMetadata>[];
    final directories = <String>[rootPath];
    while (directories.isNotEmpty) {
      final current = Directory(directories.removeLast());
      try {
        await for (final entity in current.list(followLinks: false)) {
          if (entity is Directory) {
            directories.add(entity.path);
            continue;
          }
          if (entity is! File || !_isAudio(entity.path)) continue;
          visited++;
          final filePath = p.normalize(entity.absolute.path);
          seenPaths.add(filePath);
          final metadata = await _readTrack(entity);
          if (metadata != null) {
            pending.add(metadata);
            imported++;
          }
          if (pending.length >= 48) {
            await _database.upsertTracks(List<TrackMetadata>.of(pending));
            pending.clear();
          }
          if (visited % 32 == 0) onProgress?.call(visited, imported);
        }
      } on FileSystemException catch (error) {
        _events.add('Cannot scan ${current.path}: ${error.message}');
      }
    }
    if (pending.isNotEmpty) await _database.upsertTracks(pending);
    for (final path in await _database.pathsUnder(rootPath)) {
      if (!seenPaths.contains(path)) await _database.removeTrack(path);
    }
    onProgress?.call(visited, imported);
    _events.add('Indexed $imported of $visited audio files');
    return imported;
  }

  Future<void> startWatching(List<String> roots) async {
    for (final root in roots) {
      if (!await Directory(root).exists()) continue;
      await _watchTree(root);
    }
  }

  Future<void> _watchTree(String root) async {
    final pending = <String>[root];
    while (pending.isNotEmpty) {
      final path = p.normalize(pending.removeLast());
      if (_watchSubscriptions.containsKey(path)) continue;
      try {
        final watcher = DirectoryWatcher(path);
        _watchSubscriptions[path] = watcher.events.listen(
          (event) async {
            final changedPath = p.normalize(p.absolute(event.path));
            try {
              if (event.type == ChangeType.REMOVE) {
                if (_isAudio(changedPath)) {
                  await _database.removeTrack(changedPath);
                  _events.add('Removed ${p.basename(changedPath)}');
                } else {
                  await _removeWatchersUnder(changedPath);
                  await _database.removeTracksUnder(changedPath);
                }
                return;
              }
              if (Directory(changedPath).existsSync()) {
                await _watchTree(changedPath);
              } else if (_isAudio(changedPath)) {
                await _syncFile(changedPath);
              }
            } on Object catch (error) {
              _events.add('Could not sync ${p.basename(changedPath)}: $error');
            }
          },
          onError: (Object error) {
            _events.add('Folder watch stopped for $path: $error');
          },
        );
        await for (final entity in Directory(path).list(followLinks: false)) {
          if (entity is Directory) pending.add(entity.path);
        }
      } on FileSystemException catch (error) {
        _events.add('Cannot watch $path: ${error.message}');
      }
    }
  }

  Future<void> _syncFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    final metadata = await _readTrack(file);
    if (metadata == null) return;
    await _database.upsertTracks([metadata]);
    _events.add('Updated ${p.basename(path)}');
  }

  Future<void> _removeWatchersUnder(String directory) async {
    final prefix = '$directory${Platform.pathSeparator}';
    final paths = _watchSubscriptions.keys
        .where((path) => path == directory || path.startsWith(prefix))
        .toList(growable: false);
    for (final path in paths) {
      await _watchSubscriptions.remove(path)?.cancel();
    }
  }

  Future<TrackMetadata?> _readTrack(File file) async {
    try {
      final stat = await file.stat();
      final fallbackTitle = p
          .basenameWithoutExtension(file.path)
          .replaceAll('_', ' ');
      Metadata? metadata;
      try {
        metadata = await MetadataGod.readMetadata(file: file.path);
      } on Object {
        metadata = null;
      }
      final picture = metadata?.picture?.data;
      final artwork = picture != null && picture.isNotEmpty
          ? picture
          : await _folderArtwork(file.parent);
      return TrackMetadata(
        path: file.absolute.path,
        title: _nonEmpty(metadata?.title, fallbackTitle),
        artist: _nonEmpty(metadata?.artist, 'Unknown artist'),
        album: _nonEmpty(metadata?.album, 'Unknown album'),
        genre: _nonEmpty(metadata?.genre, ''),
        year: metadata?.year,
        durationMs: metadata?.durationMs?.round() ?? 0,
        trackNumber: metadata?.trackNumber,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
        fileSize: stat.size,
        artwork: artwork,
      );
    } on FileSystemException catch (error) {
      _events.add('Skipped ${p.basename(file.path)}: ${error.message}');
      return null;
    } on Object catch (error) {
      _events.add('Skipped ${p.basename(file.path)}: $error');
      return null;
    }
  }

  Future<Uint8List?> _folderArtwork(Directory directory) async {
    for (final name in ['cover.jpg', 'cover.png', 'folder.jpg', 'folder.png']) {
      try {
        final candidate = File(p.join(directory.path, name));
        if (await candidate.exists()) return await candidate.readAsBytes();
      } on FileSystemException {
        continue;
      }
    }
    return null;
  }

  bool _isAudio(String path) => supportsAudioPath(path);

  String _nonEmpty(String? value, String fallback) =>
      value == null || value.trim().isEmpty ? fallback : value.trim();

  Future<void> dispose() async {
    for (final subscription in _watchSubscriptions.values) {
      await subscription.cancel();
    }
    await _events.close();
  }
}
