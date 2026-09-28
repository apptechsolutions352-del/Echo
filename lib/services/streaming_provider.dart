import '../models/track.dart';

/// A provider-neutral description of a track returned by a streaming service.
///
/// [playbackUri] is a URL or URI the configured player can open. Services that
/// require signed URLs should resolve them immediately before playback.
class StreamingTrack {
  const StreamingTrack({
    required this.providerId,
    required this.id,
    required this.title,
    required this.playbackUri,
    this.artist = '',
    this.album = '',
    this.duration,
    this.artworkUri,
  });

  final String providerId;
  final String id;
  final String title;
  final String playbackUri;
  final String artist;
  final String album;
  final Duration? duration;
  final String? artworkUri;

  /// Convert to the existing playback model. The remote identifier stays in
  /// the URI; remote tracks are not inserted into the local SQLite library.
  Track toTrack() => Track(
    id: -1,
    path: playbackUri,
    title: title,
    artist: artist,
    album: album,
    genre: '',
    year: null,
    durationMs: duration?.inMilliseconds ?? 0,
    trackNumber: null,
    modifiedMs: 0,
  );
}

/// Provider adapter implemented by each streaming service integration.
///
/// OAuth, API credentials, catalog search, and playback resolution differ by
/// service, so implementations own their authentication and HTTP client.
abstract interface class StreamingProvider {
  /// Stable key used for settings and provider lookup.
  String get id;

  /// Human-readable provider name.
  String get name;

  /// Whether this provider currently has an authenticated account.
  Future<bool> get isConnected;

  /// Start the provider's supported authorization flow.
  Future<void> connect();

  /// Revoke local credentials and disconnect.
  Future<void> disconnect();

  /// Search the provider catalog.
  Future<List<StreamingTrack>> search(String query, {int limit = 25});

  /// Resolve a catalog item to a playable URI. Implementations should refresh
  /// expiring links here rather than persisting them.
  Future<StreamingTrack> resolve(StreamingTrack track);
}

/// Registry used by UI and playback code to discover service adapters.
class StreamingProviderRegistry {
  StreamingProviderRegistry(Iterable<StreamingProvider> providers)
    : _providers = {for (final provider in providers) provider.id: provider};

  final Map<String, StreamingProvider> _providers;

  List<StreamingProvider> get providers => List.unmodifiable(_providers.values);

  StreamingProvider? operator [](String id) => _providers[id];

  void register(StreamingProvider provider) => _providers[provider.id] = provider;

  bool unregister(String id) => _providers.remove(id) != null;
}
