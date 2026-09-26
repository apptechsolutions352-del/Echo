import 'dart:typed_data';

class Track {
  const Track({
    required this.id,
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.year,
    required this.durationMs,
    required this.trackNumber,
    required this.modifiedMs,
    this.artwork,
  });

  final int id;
  final String path;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final int? year;
  final int durationMs;
  final int? trackNumber;
  final int modifiedMs;
  final Uint8List? artwork;

  Duration get duration => Duration(milliseconds: durationMs);

  factory Track.fromMap(Map<String, Object?> row) => Track(
    id: row['id']! as int,
    path: row['path']! as String,
    title: row['title']! as String,
    artist: row['artist']! as String,
    album: row['album']! as String,
    genre: row['genre']! as String,
    year: row['year'] as int?,
    durationMs: row['duration_ms']! as int,
    trackNumber: row['track_number'] as int?,
    modifiedMs: row['modified_ms']! as int,
    artwork: row['artwork'] as Uint8List?,
  );
}

class TrackMetadata {
  const TrackMetadata({
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.durationMs,
    required this.modifiedMs,
    required this.fileSize,
    this.year,
    this.trackNumber,
    this.artwork,
  });

  final String path;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final int durationMs;
  final int modifiedMs;
  final int fileSize;
  final int? year;
  final int? trackNumber;
  final Uint8List? artwork;
}
