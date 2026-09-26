import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../data/library_database.dart';

class M3uService {
  M3uService(this._database);

  final LibraryDatabase _database;

  Future<int> importFile(File file) async {
    final playlistName = p.basenameWithoutExtension(file.path).trim();
    if (playlistName.isEmpty) {
      throw const FormatException('Playlist file has no name');
    }
    final lines = const LineSplitter().convert(await file.readAsString());
    final root = p.dirname(file.absolute.path);
    final tracks = await _database.tracks();
    final byPath = {for (final track in tracks) p.normalize(track.path): track};
    final playlistId = await _database.createPlaylist(playlistName);
    var imported = 0;
    for (var line in lines) {
      final value = line.trim().replaceFirst('\uFEFF', '');
      if (value.isEmpty || value.startsWith('#')) continue;
      final path = value.startsWith('file:')
          ? Uri.parse(value).toFilePath()
          : p.normalize(p.isAbsolute(value) ? value : p.join(root, value));
      final track = byPath[path];
      if (track == null) continue;
      await _database.addToPlaylist(playlistId, track.id);
      imported++;
    }
    return imported;
  }

  Future<Uri?> exportPlaylist(int playlistId, String name) async {
    final tracks = await _database.playlistTracks(playlistId);
    final output = StringBuffer('#EXTM3U\n');
    for (final track in tracks) {
      output
        ..write(
          '#EXTINF:${track.duration.inSeconds},${track.artist} - ${track.title}\n',
        )
        ..write('${Uri.file(track.path).toString()}\n');
    }
    return FilePicker.saveFile(
      fileName: '${_safeName(name)}.m3u8',
      bytes: Uint8List.fromList(utf8.encode(output.toString())),
      mimeType: 'audio/x-mpegurl',
      dialogTitle: 'Export playlist',
      type: FileType.custom,
      allowedExtensions: const ['m3u', 'm3u8'],
    );
  }

  String _safeName(String value) =>
      value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}
