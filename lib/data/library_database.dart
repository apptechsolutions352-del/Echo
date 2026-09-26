import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/track.dart';

class LibraryDatabase {
  LibraryDatabase._(this._db);

  final Database _db;

  static Future<LibraryDatabase> open() async {
    final support = await getApplicationSupportDirectory();
    await support.create(recursive: true);
    final db = await databaseFactoryFfi.openDatabase(
      p.join(support.path, 'echo-library.sqlite3'),
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
          await database.execute('PRAGMA busy_timeout = 5000');
          await database.execute('PRAGMA journal_mode = WAL');
        },
        onCreate: (database, version) async {
          await database.execute(
            'CREATE TABLE artists (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE COLLATE NOCASE)',
          );
          await database.execute('''
            CREATE TABLE albums (
              id INTEGER PRIMARY KEY, title TEXT NOT NULL COLLATE NOCASE,
              artist_id INTEGER REFERENCES artists(id) ON DELETE SET NULL,
              year INTEGER, artwork BLOB, UNIQUE(title, artist_id)
            )
          ''');
          await database.execute('''
            CREATE TABLE tracks (
              id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE, title TEXT NOT NULL,
              artist_id INTEGER REFERENCES artists(id) ON DELETE SET NULL,
              album_id INTEGER REFERENCES albums(id) ON DELETE SET NULL,
              genre TEXT NOT NULL DEFAULT '', year INTEGER,
              duration_ms INTEGER NOT NULL DEFAULT 0, track_number INTEGER,
              file_size INTEGER NOT NULL DEFAULT 0, modified_ms INTEGER NOT NULL,
              added_ms INTEGER NOT NULL
            )
          ''');
          await database.execute(
            'CREATE INDEX tracks_title_idx ON tracks(title COLLATE NOCASE)',
          );
          await database.execute(
            'CREATE INDEX tracks_artist_idx ON tracks(artist_id)',
          );
          await database.execute(
            'CREATE INDEX tracks_album_idx ON tracks(album_id)',
          );
          await database.execute(
            'CREATE TABLE library_roots (path TEXT PRIMARY KEY, added_ms INTEGER NOT NULL)',
          );
          await database.execute(
            'CREATE TABLE playlists (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE COLLATE NOCASE, created_ms INTEGER NOT NULL)',
          );
          await database.execute('''
            CREATE TABLE playlist_tracks (
              playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
              track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
              position INTEGER NOT NULL, PRIMARY KEY(playlist_id, track_id)
            )
          ''');
          await database.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await database.execute(
            'CREATE TABLE equalizer_presets (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE COLLATE NOCASE, gains TEXT NOT NULL, is_builtin INTEGER NOT NULL DEFAULT 0)',
          );
          const presets = <String, String>{
            'Flat': '0,0,0,0,0,0,0,0,0,0',
            'Rock': '4,3,1,-1,-2,1,3,4,4,4',
            'Pop': '-1,2,4,4,2,-1,-1,0,1,1',
            'Jazz': '3,2,1,2,-2,-2,0,1,3,4',
            'Bass Boost': '6,5,4,2,0,0,0,0,0,0',
            'Treble Boost': '0,0,0,0,0,0,2,4,5,6',
          };
          for (final preset in presets.entries) {
            await database.insert('equalizer_presets', {
              'name': preset.key,
              'gains': preset.value,
              'is_builtin': 1,
            });
          }
        },
      ),
    );
    return LibraryDatabase._(db);
  }

  Future<List<Track>> tracks({String orderBy = 'title'}) async {
    const orders = <String, String>{
      'title': 't.title COLLATE NOCASE',
      'artist': 'a.name COLLATE NOCASE, t.title COLLATE NOCASE',
      'album': 'b.title COLLATE NOCASE, t.track_number, t.title COLLATE NOCASE',
      'year': 't.year DESC, t.title COLLATE NOCASE',
      'genre': 't.genre COLLATE NOCASE, t.title COLLATE NOCASE',
    };
    final rows = await _db.rawQuery('''
      SELECT t.*, COALESCE(a.name, 'Unknown artist') AS artist,
        COALESCE(b.title, 'Unknown album') AS album, b.artwork
      FROM tracks t LEFT JOIN artists a ON a.id=t.artist_id
      LEFT JOIN albums b ON b.id=t.album_id ORDER BY ${orders[orderBy] ?? orders['title']}
    ''');
    return rows.map(Track.fromMap).toList(growable: false);
  }

  Future<void> addRoot(String path) => _db.insert('library_roots', {
    'path': p.normalize(path),
    'added_ms': DateTime.now().millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<List<String>> roots() async => (await _db.query(
    'library_roots',
    orderBy: 'added_ms',
  )).map((row) => row['path']! as String).toList(growable: false);

  Future<void> removeRoot(String path) async {
    await _db.transaction((txn) async {
      await txn.delete('library_roots', where: 'path = ?', whereArgs: [path]);
      await txn.delete('tracks', where: 'path = ?', whereArgs: [path]);
      await txn.rawDelete(
        'DELETE FROM tracks WHERE substr(path, 1, length(?)) = ?',
        ['$path${Platform.pathSeparator}', '$path${Platform.pathSeparator}'],
      );
    });
  }

  Future<List<String>> pathsUnder(String root) async {
    final prefix = '$root${Platform.pathSeparator}';
    final rows = await _db.rawQuery(
      'SELECT path FROM tracks WHERE path = ? OR substr(path, 1, length(?)) = ?',
      [root, prefix, prefix],
    );
    return rows.map((row) => row['path']! as String).toList(growable: false);
  }

  Future<void> removeTracksUnder(String root) async {
    final prefix = '$root${Platform.pathSeparator}';
    await _db.rawDelete(
      'DELETE FROM tracks WHERE path = ? OR substr(path, 1, length(?)) = ?',
      [root, prefix, prefix],
    );
  }

  Future<void> upsertTracks(List<TrackMetadata> tracks) async {
    await _db.transaction((txn) async {
      for (final track in tracks) {
        await txn.rawInsert(
          'INSERT INTO artists(name) VALUES(?) ON CONFLICT(name) DO NOTHING',
          [track.artist],
        );
        final artist = (await txn.query(
          'artists',
          columns: ['id'],
          where: 'name = ?',
          whereArgs: [track.artist],
        )).single;
        await txn.rawInsert(
          'INSERT INTO albums(title, artist_id, year, artwork) VALUES(?, ?, ?, ?) '
          'ON CONFLICT(title, artist_id) DO UPDATE SET year=excluded.year, artwork=COALESCE(excluded.artwork, albums.artwork)',
          [track.album, artist['id'], track.year, track.artwork],
        );
        final album = (await txn.query(
          'albums',
          columns: ['id'],
          where: 'title = ? AND artist_id = ?',
          whereArgs: [track.album, artist['id']],
        )).single;
        await txn.rawInsert(
          '''
          INSERT INTO tracks(
            path, title, artist_id, album_id, genre, year, duration_ms,
            track_number, file_size, modified_ms, added_ms
          ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(path) DO UPDATE SET
            title=excluded.title,
            artist_id=excluded.artist_id,
            album_id=excluded.album_id,
            genre=excluded.genre,
            year=excluded.year,
            duration_ms=excluded.duration_ms,
            track_number=excluded.track_number,
            file_size=excluded.file_size,
            modified_ms=excluded.modified_ms
          ''',
          [
            track.path,
            track.title,
            artist['id'],
            album['id'],
            track.genre,
            track.year,
            track.durationMs,
            track.trackNumber,
            track.fileSize,
            track.modifiedMs,
            DateTime.now().millisecondsSinceEpoch,
          ],
        );
      }
    });
  }

  Future<void> removeTrack(String path) =>
      _db.delete('tracks', where: 'path = ?', whereArgs: [path]);

  Future<List<Map<String, Object?>>> playlists() => _db.rawQuery('''
    SELECT p.id, p.name, COUNT(pt.track_id) AS track_count FROM playlists p
    LEFT JOIN playlist_tracks pt ON pt.playlist_id=p.id GROUP BY p.id ORDER BY p.name COLLATE NOCASE
  ''');

  Future<int> createPlaylist(String name) => _db.insert('playlists', {
    'name': name.trim(),
    'created_ms': DateTime.now().millisecondsSinceEpoch,
  });

  Future<void> deletePlaylist(int id) =>
      _db.delete('playlists', where: 'id = ?', whereArgs: [id]);

  Future<void> addToPlaylist(int playlistId, int trackId) async {
    final countRows = await _db.rawQuery(
      'SELECT COUNT(*) FROM playlist_tracks WHERE playlist_id=?',
      [playlistId],
    );
    final count = countRows.first.values.first as int;
    await _db.insert('playlist_tracks', {
      'playlist_id': playlistId,
      'track_id': trackId,
      'position': count,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Track>> playlistTracks(int playlistId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT t.*, COALESCE(a.name, 'Unknown artist') AS artist,
        COALESCE(b.title, 'Unknown album') AS album, b.artwork
      FROM playlist_tracks pt JOIN tracks t ON t.id=pt.track_id
      LEFT JOIN artists a ON a.id=t.artist_id LEFT JOIN albums b ON b.id=t.album_id
      WHERE pt.playlist_id=? ORDER BY pt.position
    ''',
      [playlistId],
    );
    return rows.map(Track.fromMap).toList(growable: false);
  }

  Future<void> saveSetting(String key, String value) => _db.insert('settings', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<String?> setting(String key) async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.single['value']! as String;
  }

  Future<void> close() => _db.close();
}
