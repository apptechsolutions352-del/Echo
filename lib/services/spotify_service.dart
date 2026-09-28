import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:spotify/spotify.dart';

import '../models/unified_playlist.dart';
import 'streaming_service.dart';

/// Spotify Web API adapter for playlist metadata.
///
/// Uses OAuth Authorization Code with PKCE: the desktop app is a public
/// client, so it must never embed a Spotify client secret. Spotify's redirect
/// URI must exactly match http://127.0.0.1:8080/callback in the dashboard.
class SpotifyService implements StreamingService {
  SpotifyService({required this.clientId});

  final String clientId;
  static const _redirectUri = 'http://127.0.0.1:8080/callback';
  static const _scopes = <String>[
    'playlist-read-private',
    'playlist-read-collaborative',
  ];

  SpotifyApi? _api;

  @override
  String get serviceName => 'Spotify';

  @override
  bool get isConnected => _api != null;

  @override
  Future<bool> login() async {
    if (clientId.trim().isEmpty) {
      throw StateError('Set a Spotify developer client ID before connecting.');
    }

    final verifier = SpotifyApi.generateCodeVerifier();
    final credentials = SpotifyApiCredentials.pkce(
      clientId,
      codeVerifier: verifier,
    );
    final grant = SpotifyApi.authorizationCodeGrant(credentials);
    final state = _secureRandomString(32);
    final callback = Uri.parse(_redirectUri);
    final authorizeUri = grant.getAuthorizationUrl(
      callback,
      scopes: _scopes,
      state: state,
    );

    final server = await shelf_io.serve(
      _callbackHandler(state),
      InternetAddress.loopbackIPv4,
      8080,
      poweredByHeader: null,
    );

    try {
      await Process.start('xdg-open', [authorizeUri.toString()]);
      final params = await _authorizationCompleter!.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw TimeoutException('Spotify login timed out.'),
      );
      final client = await grant.handleAuthorizationResponse(params);
      _api = SpotifyApi.fromClient(client);
      return true;
    } finally {
      await server.close(force: true);
      _authorizationCompleter = null;
    }
  }

  Handler _callbackHandler(String expectedState) {
    final completer = Completer<Map<String, String>>();
    _authorizationCompleter = completer;

    return (Request request) async {
      if (request.url.path != 'callback') {
        return Response.notFound('Not found');
      }

      final query = request.url.queryParameters;
      if (query['state'] != expectedState) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('OAuth state validation failed.'));
        }
        return Response.forbidden('Invalid OAuth state. You may close this tab.');
      }
      if (query.containsKey('error')) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('Spotify authorization failed: ${query['error']}'),
          );
        }
        return Response.ok('Spotify authorization was not granted. You may close this tab.');
      }
      if (query['code'] == null || query['code']!.isEmpty) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('Spotify did not return an authorization code.'));
        }
        return Response.badRequest(body: 'Missing authorization code.');
      }

      if (!completer.isCompleted) completer.complete(query);
      return Response.ok(
        '<!doctype html><html><body><h2>Spotify connected</h2>'
        '<p>You can close this tab and return to Echo.</p></body></html>',
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    };
  }

  Completer<Map<String, String>>? _authorizationCompleter;

  String _secureRandomString(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  @override
  Future<List<UnifiedPlaylist>> fetchPlaylists() async {
    final api = _api;
    if (api == null) throw StateError('Connect Spotify first.');

    final page = await api.me.playlists.saved().all();
    return page.map((dynamic playlist) {
      final dynamic images = playlist.images;
      final dynamic trackInfo = playlist.tracksLink;
    final String? imageUrl = images is List && images.isNotEmpty
          ? images.first.url as String?
          : null;
      final int count = (trackInfo?.total as num?)?.toInt() ?? 0;
      return UnifiedPlaylist(
        id: playlist.id.toString(),
        name: playlist.name?.toString() ?? 'Untitled playlist',
        imageUrl: imageUrl,
        trackCount: count,
        sourcePlatform: serviceName,
      );
    }).toList(growable: false);
  }

  @override
  Future<void> logout() async {
    // Drop the in-memory token client. Credentials are intentionally not
    // persisted by this adapter; add OS keyring storage before session restore.
    _api = null;
  }
}
