import 'dart:typed_data';

import 'package:echo/models/track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('track model preserves catalog fields and artwork', () {
    final artwork = Uint8List.fromList([1, 2, 3]);
    final track = Track.fromMap({
      'id': 12,
      'path': '/music/track.flac',
      'title': 'Track title',
      'artist': 'Artist',
      'album': 'Album',
      'genre': 'Jazz',
      'year': 2024,
      'duration_ms': 213000,
      'track_number': 4,
      'modified_ms': 1700000000,
      'artwork': artwork,
    });

    expect(track.id, 12);
    expect(track.artist, 'Artist');
    expect(track.duration.inSeconds, 213);
    expect(track.artwork, artwork);
  });
}
