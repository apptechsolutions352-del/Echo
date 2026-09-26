import 'package:echo/services/mpris_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show PlaylistMode;

void main() {
  test('MPRIS loop modes map to media_kit playlist modes', () {
    expect(MprisBridge.loopMode('None'), PlaylistMode.none);
    expect(MprisBridge.loopMode('Track'), PlaylistMode.single);
    expect(MprisBridge.loopMode('Playlist'), PlaylistMode.loop);
    expect(MprisBridge.loopMode('unknown'), PlaylistMode.none);
  });
}
