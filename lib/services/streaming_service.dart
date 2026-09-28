import '../models/unified_playlist.dart';

/// Contract consumed by UI for all streaming account integrations.
abstract interface class StreamingService {
  String get serviceName;
  bool get isConnected;

  Future<bool> login();
  Future<List<UnifiedPlaylist>> fetchPlaylists();
  Future<void> logout();
}
