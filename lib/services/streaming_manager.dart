import 'package:flutter/foundation.dart';

import '../models/unified_playlist.dart';
import 'streaming_service.dart';

/// Coordinates provider adapters while keeping platform-specific details out
/// of widgets. A single operation is tracked per service ID.
class StreamingManager extends ChangeNotifier {
  StreamingManager(Iterable<StreamingService> services)
    : _services = List.unmodifiable(services);

  final List<StreamingService> _services;
  final Set<String> _busy = {};
  final Map<String, String> _errors = {};
  List<UnifiedPlaylist> _playlists = const [];
  bool _disposed = false;

  List<StreamingService> get services => _services;
  Set<String> get busyServices => Set.unmodifiable(_busy);
  Map<String, String> get errors => Map.unmodifiable(_errors);
  List<UnifiedPlaylist> get playlists => List.unmodifiable(_playlists);

  StreamingService? service(String serviceName) {
    for (final service in _services) {
      if (service.serviceName == serviceName) return service;
    }
    return null;
  }

  Future<bool> connect(StreamingService service) async {
    if (!_begin(service)) return false;
    try {
      final connected = await service.login();
      _errors.remove(service.serviceName);
      if (connected) await _refreshServicePlaylists(service);
      return connected;
    } on Object catch (error) {
      _errors[service.serviceName] = error.toString();
      return false;
    } finally {
      _finish(service);
    }
  }

  Future<void> disconnect(StreamingService service) async {
    if (!_begin(service)) return;
    try {
      await service.logout();
      _playlists = _playlists
          .where((playlist) => playlist.sourcePlatform != service.serviceName)
          .toList(growable: false);
      _errors.remove(service.serviceName);
    } on Object catch (error) {
      _errors[service.serviceName] = error.toString();
    } finally {
      _finish(service);
    }
  }

  Future<void> refreshPlaylists() async {
    for (final provider in _services.where((service) => service.isConnected)) {
      if (!_begin(provider)) continue;
      try {
        await _refreshServicePlaylists(provider);
        _errors.remove(provider.serviceName);
      } on Object catch (error) {
        _errors[provider.serviceName] = error.toString();
      } finally {
        _finish(provider);
      }
    }
  }

  bool _begin(StreamingService service) {
    if (_disposed || !_services.contains(service) ||
        !_busy.add(service.serviceName)) {
      return false;
    }
    _notify();
    return true;
  }

  void _finish(StreamingService service) {
    _busy.remove(service.serviceName);
    _notify();
  }

  Future<void> _refreshServicePlaylists(StreamingService service) async {
    if (!service.isConnected) return;
    final fresh = await service.fetchPlaylists();
    _playlists = [
      ..._playlists.where(
        (playlist) => playlist.sourcePlatform != service.serviceName,
      ),
      ...fresh,
    ];
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
