import '../models/unified_playlist.dart';
import 'streaming_service.dart';

/// Integration boundary for Apple Music.
///
/// Apple Music requires a developer token signed with a private key and a
/// Music User Token for a user's library. Keep private-key signing on a trusted
/// backend; never bundle the .p8 key in a desktop application. This class
/// stays disconnected until those backend and user authorization flows exist.
class AppleMusicService implements StreamingService {
  @override
  String get serviceName => 'Apple Music';

  @override
  bool get isConnected => false;

  @override
  Future<bool> login() async => throw UnimplementedError(
    'Apple Music login requires a developer-token and Music User Token flow.',
  );

  @override
  Future<List<UnifiedPlaylist>> fetchPlaylists() async =>
      throw UnimplementedError(
        'Call Apple Music API GET /v1/me/library/playlists after authorization.',
      );

  @override
  Future<void> logout() async {}
}
