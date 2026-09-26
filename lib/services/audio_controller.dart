import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart'
    show Media, NativePlayer, Player, Playlist, PlaylistMode;

import '../models/track.dart';
import 'mpris_bridge.dart';

class AudioController {
  final Player player = Player();
  final ValueNotifier<Track?> currentTrack = ValueNotifier(null);
  final ValueNotifier<bool> playing = ValueNotifier(false);
  final ValueNotifier<bool> shuffle = ValueNotifier(false);
  final ValueNotifier<PlaylistMode> repeat = ValueNotifier(PlaylistMode.none);
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);
  final ValueNotifier<double> volume = ValueNotifier(100);
  final ValueNotifier<String?> error = ValueNotifier(null);
  late final MprisBridge _mpris;
  List<Track> _queue = const [];
  final List<StreamSubscription<Object?>> _subscriptions = [];
  int _lastPublishedSecond = -1;
  double _lastAudibleVolume = 100;
  String _playbackStatus = 'Stopped';

  AudioController() {
    _mpris = MprisBridge(onCommand: _handleMprisCommand);
    currentTrack.addListener(_publishMetadata);
    playing.addListener(_publishPlayback);
    volume.addListener(_publishSettings);
    shuffle.addListener(_publishSettings);
    repeat.addListener(_publishSettings);
    _subscriptions
      ..add(player.stream.playing.listen((value) => playing.value = value))
      ..add(
        player.stream.position.listen((value) {
          position.value = value;
          if (value.inSeconds != _lastPublishedSecond) {
            _lastPublishedSecond = value.inSeconds;
            unawaited(_mpris.publishPosition(value));
          }
        }),
      )
      ..add(player.stream.duration.listen((value) => duration.value = value))
      ..add(
        player.stream.volume.listen((value) {
          volume.value = value;
          if (value > 0) _lastAudibleVolume = value;
        }),
      )
      ..add(player.stream.shuffle.listen((value) => shuffle.value = value))
      ..add(player.stream.playlistMode.listen((value) => repeat.value = value))
      ..add(player.stream.error.listen((value) => error.value = value))
      ..add(
        player.stream.playlist.listen((value) {
          if (value.index >= 0 && value.index < _queue.length) {
            currentTrack.value = _queue[value.index];
            position.value = Duration.zero;
          }
        }),
      );
  }

  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    final validTracks = tracks.where((track) => track.path.isNotEmpty).toList();
    if (validTracks.isEmpty) return;
    final selectedIndex = startIndex.clamp(0, validTracks.length - 1);
    _queue = validTracks;
    _playbackStatus = 'Playing';
    error.value = null;
    try {
      await player.open(
        Playlist(
          validTracks.map((track) => Media(track.path)).toList(),
          index: selectedIndex,
        ),
      );
      currentTrack.value = validTracks[selectedIndex];
    } on Object catch (exception) {
      _playbackStatus = 'Stopped';
      error.value = 'Unable to play this track: $exception';
    }
  }

  Future<void> togglePlay() async {
    try {
      await player.playOrPause();
    } on Object catch (exception) {
      error.value = 'Playback control failed: $exception';
    }
  }

  Future<void> next() async =>
      _guard(player.next, 'Could not skip to the next track');
  Future<void> previous() async =>
      _guard(player.previous, 'Could not return to the previous track');
  Future<void> seek(Duration value) async =>
      _guard(() => player.seek(value), 'Could not seek in this track');

  Future<void> _handleMprisCommand(String method, Object? arguments) async {
    try {
      switch (method) {
        case 'Play':
          _playbackStatus = 'Playing';
          await player.play();
        case 'Pause':
          _playbackStatus = 'Paused';
          await player.pause();
        case 'PlayPause':
          await player.playOrPause();
        case 'Stop':
          _playbackStatus = 'Stopped';
          await player.stop();
        case 'Next':
          await player.next();
        case 'Previous':
          await player.previous();
        case 'Seek':
          if (arguments is int) {
            await player.seek(
              position.value + Duration(microseconds: arguments),
            );
          }
        case 'SetPosition':
          if (arguments is List &&
              arguments.length == 2 &&
              arguments[1] is int) {
            await player.seek(Duration(microseconds: arguments[1] as int));
          }
        case 'SetVolume':
          if (arguments is num) await setVolume(arguments.toDouble());
        case 'SetShuffle':
          if (arguments is bool) await player.setShuffle(arguments);
        case 'SetLoopStatus':
          if (arguments is String) {
            await player.setPlaylistMode(MprisBridge.loopMode(arguments));
          }
        case 'OpenUri':
          if (arguments is String) {
            _queue = const [];
            currentTrack.value = null;
            await player.open(Media(arguments));
          }
      }
    } on Object catch (exception) {
      error.value = 'MPRIS command failed: $exception';
    }
  }

  void _publishMetadata() {
    final track = currentTrack.value;
    unawaited(
      _mpris.publishMetadata(
        title: track?.title ?? '',
        artist: track?.artist ?? '',
        album: track?.album ?? '',
      ),
    );
  }

  void _publishPlayback() {
    if (playing.value) {
      _playbackStatus = 'Playing';
    } else if (_playbackStatus == 'Playing') {
      _playbackStatus = 'Paused';
    }
    unawaited(_mpris.publishPlayback(_playbackStatus));
  }

  void _publishSettings() => unawaited(
    _mpris.publishSettings(
      volume: volume.value.clamp(0, 100),
      shuffle: shuffle.value,
      repeat: repeat.value,
    ),
  );

  Future<void> toggleShuffle() async {
    try {
      await player.setShuffle(!shuffle.value);
    } on Object catch (exception) {
      error.value = 'Could not change shuffle: $exception';
    }
  }

  Future<void> cycleRepeat() async {
    final nextMode = switch (repeat.value) {
      PlaylistMode.none => PlaylistMode.loop,
      PlaylistMode.loop => PlaylistMode.single,
      PlaylistMode.single => PlaylistMode.none,
    };
    try {
      await player.setPlaylistMode(nextMode);
    } on Object catch (exception) {
      error.value = 'Could not change repeat mode: $exception';
    }
  }

  Future<void> setVolume(double value) async {
    try {
      final bounded = value.clamp(0, 200).toDouble();
      final platform = player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('volume-max', '200');
      }
      await player.setVolume(bounded);
      if (bounded > 0) _lastAudibleVolume = bounded;
    } on Object catch (exception) {
      error.value = 'Could not change volume: $exception';
    }
  }

  Future<void> toggleMute() =>
      setVolume(volume.value == 0 ? _lastAudibleVolume : 0);

  Future<void> _guard(Future<void> Function() action, String message) async {
    try {
      await action();
    } on Object catch (exception) {
      error.value = '$message: $exception';
    }
  }

  Future<void> dispose() async {
    currentTrack.removeListener(_publishMetadata);
    playing.removeListener(_publishPlayback);
    volume.removeListener(_publishSettings);
    shuffle.removeListener(_publishSettings);
    repeat.removeListener(_publishSettings);
    _mpris.dispose();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    currentTrack.dispose();
    playing.dispose();
    shuffle.dispose();
    repeat.dispose();
    position.dispose();
    duration.dispose();
    volume.dispose();
    error.dispose();
    await player.dispose();
  }
}
