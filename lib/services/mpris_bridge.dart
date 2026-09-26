import 'dart:io';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' show PlaylistMode;

class MprisBridge {
  MprisBridge({required this.onCommand}) {
    if (Platform.isLinux) {
      _channel.setMethodCallHandler(_handleCall);
    }
  }

  static const _channel = MethodChannel('org.echo.Echo/mpris');
  final Future<void> Function(String method, Object? arguments) onCommand;

  Future<void> publishMetadata({
    required String title,
    required String artist,
    required String album,
  }) async {
    if (!Platform.isLinux) return;
    await _invoke('updateMetadata', {
      'title': title,
      'artist': artist,
      'album': album,
    });
  }

  Future<void> publishPlayback(String status) async {
    await _invoke('updatePlayback', {'status': status});
  }

  Future<void> publishPosition(Duration position) async {
    if (!Platform.isLinux) return;
    await _invoke('updatePosition', position.inMicroseconds);
  }

  Future<void> publishSettings({
    required double volume,
    required bool shuffle,
    required PlaylistMode repeat,
  }) => _invoke('updateSettings', {
    'volume': volume / 100,
    'shuffle': shuffle,
    'loopStatus': switch (repeat) {
      PlaylistMode.none => 'None',
      PlaylistMode.single => 'Track',
      PlaylistMode.loop => 'Playlist',
    },
  });

  Future<void> _invoke(String method, Object? arguments) async {
    if (!Platform.isLinux) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException {
      // The desktop bus service may not be available in sandboxed sessions.
    } on MissingPluginException {
      // Non-Linux runner builds do not register the Linux bridge.
    }
  }

  Future<void> _handleCall(MethodCall call) =>
      onCommand(call.method, call.arguments);

  void dispose() {
    if (Platform.isLinux) _channel.setMethodCallHandler(null);
  }

  static PlaylistMode loopMode(String value) => switch (value) {
    'Track' => PlaylistMode.single,
    'Playlist' => PlaylistMode.loop,
    _ => PlaylistMode.none,
  };
}
