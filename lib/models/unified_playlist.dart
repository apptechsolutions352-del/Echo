/// Provider-independent playlist summary for the streaming library UI.
class UnifiedPlaylist {
  const UnifiedPlaylist({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.sourcePlatform,
    this.imageUrl,
    this.openUrl,
  });

  final String id;
  final String name;
  final String? imageUrl;
  final int trackCount;
  final String sourcePlatform;

  /// A provider deep link when the service exposes one.
  final Uri? openUrl;
}
