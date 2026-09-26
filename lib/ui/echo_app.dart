import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
import 'package:media_kit/media_kit.dart' show PlaylistMode;
import 'package:path/path.dart' as p;

import '../data/library_database.dart';
import '../models/track.dart';
import '../services/audio_controller.dart';
import '../services/library_scanner.dart';
import '../services/m3u_service.dart';

final _brightness = ValueNotifier(Brightness.dark);
Color _ink = const Color(0xFFF1EFF4);
Color _surface = const Color(0xFF171719);
Color _teal = const Color(0xFF9B72CF);
Color _muted = const Color(0xFFA6A2AA);
Color _panel = const Color(0xFF202023);
Color _line = const Color(0xFF353439);
TextStyle get _columnLabelStyle => TextStyle(
  color: _muted,
  fontSize: 10,
  fontWeight: FontWeight.w600,
  letterSpacing: 1,
);

class EchoApp extends StatelessWidget {
  const EchoApp({
    super.key,
    required this.database,
    required this.scanner,
    required this.audio,
    this.initialFiles = const [],
  });

  final LibraryDatabase database;
  final LibraryScanner scanner;
  final AudioController audio;
  final List<String> initialFiles;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Brightness>(
    valueListenable: _brightness,
    builder: (context, brightness, _) {
      final isDark = brightness == Brightness.dark;
      _ink = isDark ? const Color(0xFFF1EFF4) : const Color(0xFF202023);
      _surface = isDark ? const Color(0xFF171719) : const Color(0xFFF7F6F8);
      _teal = isDark ? const Color(0xFFB99AE3) : const Color(0xFF7046A8);
      _muted = isDark ? const Color(0xFFA6A2AA) : const Color(0xFF66616B);
      _panel = isDark ? const Color(0xFF202023) : const Color(0xFFFFFFFF);
      _line = isDark ? const Color(0xFF353439) : const Color(0xFFDDDAE0);
      return MaterialApp(
    title: 'Echo',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: _surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _teal,
        brightness: brightness,
      ),
      fontFamily: 'Noto Sans',
      appBarTheme: AppBarTheme(
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: _line,
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: _ink,
        displayColor: _ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: _muted),
        labelStyle: TextStyle(color: _muted),
      ),
    ),
    home: _EchoHome(
        database: database,
        scanner: scanner,
        audio: audio,
        initialFiles: initialFiles,
      ),
    );
    },
  );
}

enum _Section { search, music, playlists, nowPlaying, settings }

enum _LibraryTab { songs, artists, albums }

class _EchoHome extends StatefulWidget {
  const _EchoHome({
    required this.database,
    required this.scanner,
    required this.audio,
    required this.initialFiles,
  });
  final LibraryDatabase database;
  final LibraryScanner scanner;
  final AudioController audio;
  final List<String> initialFiles;

  @override
  State<_EchoHome> createState() => _EchoHomeState();
}

class _EchoHomeState extends State<_EchoHome> {
  _Section _section = _Section.music;
  _LibraryTab _tab = _LibraryTab.songs;
  bool _sidebarExpanded = true;
  bool _busy = false;
  String _sort = 'title';
  String? _folder;
  String _query = '';
  String? _message;
  bool _dropActive = false;
  Color _ambientColor = const Color(0xFF173B3B);
  List<Track> _tracks = const [];
  List<String> _roots = const [];
  List<Map<String, Object?>> _playlists = const [];
  final _searchController = TextEditingController();
  StreamSubscription<String>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _scanSubscription = widget.scanner.events.listen((message) {
      if (mounted) setState(() => _message = message);
    });
    widget.audio.currentTrack.addListener(_updateAmbientColor);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _load();
    final launchTracks = <Track>[];
    for (final path in widget.initialFiles) {
      if (p.extension(path).toLowerCase() == '.m3u' ||
          p.extension(path).toLowerCase() == '.m3u8') {
        try {
          final count = await M3uService(widget.database)
              .importFile(File(path));
          if (mounted) {
            setState(() => _message = 'Imported $count indexed tracks');
          }
        } on Object catch (error) {
          if (mounted) {
            setState(() => _message = 'Could not open playlist: $error');
          }
        }
      } else if (LibraryScanner.supportsAudioPath(path) &&
          await File(path).exists()) {
        await _scan(p.dirname(path));
        final normalizedPath = p.normalize(p.absolute(path));
        for (final track in _tracks) {
          if (p.normalize(track.path) == normalizedPath) {
            launchTracks.add(track);
          }
        }
      }
    }
    if (launchTracks.isNotEmpty) {
      await _play(launchTracks.first, queue: launchTracks);
    }
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        widget.database.tracks(orderBy: _sort),
        widget.database.roots(),
        widget.database.playlists(),
      ]);
      if (!mounted) return;
      setState(() {
        _tracks = values[0] as List<Track>;
        _roots = values[1] as List<String>;
        _playlists = values[2] as List<Map<String, Object?>>;
      });
      if (_roots.isEmpty) {
        final music = Directory(
          p.join(Platform.environment['HOME'] ?? '', 'Music'),
        );
        if (await music.exists()) await _scan(music.path);
      } else {
        await widget.scanner.startWatching(_roots);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = 'Library could not be opened: $error');
      }
    }
  }

  Future<void> _reload() async {
    try {
      final tracks = await widget.database.tracks(orderBy: _sort);
      final roots = await widget.database.roots();
      final playlists = await widget.database.playlists();
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _roots = roots;
        _playlists = playlists;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _message = 'Library refresh failed: $error');
    }
  }

  Future<void> _scan(String path) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = 'Scanning ${p.basename(path)}…';
    });
    try {
      final count = await widget.scanner.scanRoot(path);
      await widget.scanner.startWatching(await widget.database.roots());
      await _reload();
      if (mounted) setState(() => _message = 'Added $count tracks');
    } on Object catch (error) {
      if (mounted) setState(() => _message = 'Could not scan folder: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseFolder() async {
    try {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: 'Add a music folder',
      );
      if (path != null) await _scan(path);
    } on Object catch (error) {
      if (mounted) setState(() => _message = 'Folder picker failed: $error');
    }
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    setState(() => _dropActive = false);
    for (final item in details.files) {
      final path = item.path;
      if (path.isEmpty) continue;
      if (Directory(path).existsSync()) {
        await _scan(path);
      } else if (p.extension(path).toLowerCase() == '.m3u' ||
          p.extension(path).toLowerCase() == '.m3u8') {
        try {
          final count = await M3uService(widget.database)
              .importFile(File(path));
          await _reload();
          if (mounted) {
            setState(() => _message = 'Imported $count indexed tracks');
          }
        } on Object catch (error) {
          if (mounted) {
            setState(() => _message = 'Could not import playlist: $error');
          }
        }
      } else if (LibraryScanner.supportsAudioPath(path)) {
        await _scan(p.dirname(path));
      }
    }
  }

  Future<void> _updateAmbientColor() async {
    final bytes = widget.audio.currentTrack.value?.artwork;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) setState(() => _ambientColor = const Color(0xFF173B3B));
      return;
    }
    try {
      final value = await compute(_extractDominantColor, bytes);
      if (mounted) setState(() => _ambientColor = Color(value));
    } on Object {
      if (mounted) setState(() => _ambientColor = const Color(0xFF173B3B));
    }
  }

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      await widget.database.createPlaylist(name);
      await _reload();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = 'Could not create playlist: $error');
      }
    }
  }

  Future<void> _importPlaylist() async {
    try {
      final selection = await FilePicker.pickFiles(
        dialogTitle: 'Import playlist',
        type: FileType.custom,
        allowedExtensions: const ['m3u', 'm3u8'],
      );
      final path = selection.isEmpty ? null : selection.first.path;
      if (path == null) return;
      final count = await M3uService(widget.database).importFile(File(path));
      await _reload();
      if (mounted) setState(() => _message = 'Imported $count indexed tracks');
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = 'Could not import playlist: $error');
      }
    }
  }

  Future<void> _play(Track track, {List<Track>? queue}) async {
    final list = queue ?? _visibleTracks;
    final index = list.indexWhere((item) => item.id == track.id);
    await widget.audio.playQueue(list, startIndex: index < 0 ? 0 : index);
    if (mounted && widget.audio.error.value != null) {
      setState(() => _message = widget.audio.error.value);
    }
  }

  List<Track> get _visibleTracks => _tracks
      .where((track) {
        final query = _query.trim().toLowerCase();
        final matchesText =
            query.isEmpty ||
            '${track.title} ${track.artist} ${track.album} ${track.genre}'
                .toLowerCase()
                .contains(query);
        final matchesFolder =
            _folder == null || p.isWithin(_folder!, track.path);
        return matchesText && matchesFolder;
      })
      .toList(growable: false);

  @override
  void dispose() {
    unawaited(_scanSubscription?.cancel());
    widget.audio.currentTrack.removeListener(_updateAmbientColor);
    _searchController.dispose();
    unawaited(widget.scanner.dispose());
    unawaited(widget.audio.dispose());
    unawaited(widget.database.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                if (_section != _Section.nowPlaying) ...[
                  _sidebar(),
                  const VerticalDivider(width: 1),
                ],
                Expanded(
                  child: Column(
                    children: [
                      if (_section != _Section.nowPlaying) _topBar(),
                      if (_section != _Section.nowPlaying && _message != null)
                        _statusLine(),
                      Expanded(
                        child: DropTarget(
                          onDragEntered: (_) =>
                              setState(() => _dropActive = true),
                          onDragExited: (_) =>
                              setState(() => _dropActive = false),
                          onDragDone: (details) =>
                              unawaited(_handleDrop(details)),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 260),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                          position: Tween<Offset>(
                                            begin: const Offset(0.015, 0),
                                            end: Offset.zero,
                                          ).animate(animation),
                                          child: child,
                                        ),
                                      ),
                                  child: KeyedSubtree(
                                    key: ValueKey(_section),
                                    child: _content(),
                                  ),
                                ),
                              ),
                              if (_dropActive)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: Container(
                                      color: const Color(0x3378B9A6),
                                      alignment: Alignment.center,
                                      child: Text(
                                        'Drop music folders, audio files, or M3U playlists',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: _ink,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_section != _Section.nowPlaying) _playerBar(),
        ],
      ),
    ),
  );

  Widget _sidebar() => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
    width: _sidebarExpanded ? 224 : 68,
    color: _panel,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 70,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Collapse navigation',
                onPressed: () =>
                    setState(() => _sidebarExpanded = !_sidebarExpanded),
                icon: const Icon(Icons.menu),
              ),
              if (_sidebarExpanded)
                Text(
                  'ECHO',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    fontSize: 13,
                    color: _ink,
                  ),
                ),
            ],
          ),
        ),
        for (final item in _Section.values) _navItem(item),
        const Spacer(),
        if (_sidebarExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 18),
            child: Text(
              '${_tracks.length} songs',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ),
      ],
    ),
  );

  Widget _navItem(_Section item) {
    const labels = {
      _Section.search: 'Search',
      _Section.music: 'My Music',
      _Section.playlists: 'Playlists',
      _Section.nowPlaying: 'Now Playing',
      _Section.settings: 'Settings',
    };
    const icons = {
      _Section.search: Icons.search,
      _Section.music: Icons.library_music_outlined,
      _Section.playlists: Icons.queue_music,
      _Section.nowPlaying: Icons.graphic_eq,
      _Section.settings: Icons.settings_outlined,
    };
    final selected = _section == item;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Tooltip(
        message: _sidebarExpanded ? '' : labels[item]!,
        child: Material(
          color: selected ? const Color(0xFF352843) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => setState(() => _section = item),
            child: SizedBox(
              height: 46,
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    child: Icon(
                      icons[item],
                      color: selected ? _teal : _ink,
                      size: 21,
                    ),
                  ),
                  if (_sidebarExpanded)
                    Text(
                      labels[item]!,
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() => SizedBox(
    height: 70,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Row(
        children: [
          if (_section == _Section.search)
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Search your music',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            )
          else
            Expanded(
              child: Text(
                _heading,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
            ),
          if (_section == _Section.music || _section == _Section.search) ...[
            IconButton(
              tooltip: 'Refresh library',
              onPressed: _busy ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _chooseFolder,
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('Add folder'),
            ),
          ],
        ],
      ),
    ),
  );

  String get _heading => switch (_section) {
    _Section.search => 'Search',
    _Section.music => 'My music',
    _Section.playlists => 'Playlists',
    _Section.nowPlaying => 'Now playing',
    _Section.settings => 'Settings',
  };

  Widget _statusLine() => Container(
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 7),
    color: _busy ? const Color(0xFF30273A) : _panel,
    child: Row(
      children: [
        if (_busy)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        if (_busy) const SizedBox(width: 10),
        Expanded(
          child: Text(
            _message!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _message = null),
          icon: const Icon(Icons.close, size: 16),
        ),
      ],
    ),
  );

  Widget _content() => switch (_section) {
    _Section.music || _Section.search => _library(),
    _Section.playlists => _playlistPage(),
    _Section.nowPlaying => _nowPlaying(),
    _Section.settings => _settings(),
  };

  Widget _library() {
    final tracks = _visibleTracks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 6, 30, 0),
          child: Row(
            children: [
              for (final tab in _LibraryTab.values)
                Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: InkWell(
                    onTap: () => setState(() => _tab = tab),
                    child: Container(
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _tab == tab ? _teal : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        switch (tab) {
                          _LibraryTab.songs => 'Songs',
                          _LibraryTab.artists => 'Artists',
                          _LibraryTab.albums => 'Albums',
                        },
                        style: TextStyle(
                          color: _tab == tab ? _ink : _muted,
                          fontWeight: _tab == tab
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  initialValue: _sort,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Sort by',
                    border: InputBorder.none,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'title', child: Text('Title')),
                    DropdownMenuItem(value: 'artist', child: Text('Artist')),
                    DropdownMenuItem(value: 'album', child: Text('Album')),
                    DropdownMenuItem(
                      value: 'year',
                      child: Text('Release year'),
                    ),
                    DropdownMenuItem(value: 'genre', child: Text('Genre')),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => _sort = value);
                    await _reload();
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String?>(
                  initialValue: _folder,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Folder',
                    border: InputBorder.none,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All folders'),
                    ),
                    ..._roots.map(
                      (root) => DropdownMenuItem<String?>(
                        value: root,
                        child: Text(
                          p.basename(root),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _folder = value),
                ),
              ),
              if (_tab == _LibraryTab.songs)
                IconButton(
                  tooltip: 'Jump to letter',
                  onPressed: tracks.isEmpty ? null : _showJumpGrid,
                  icon: const Icon(Icons.sort_by_alpha),
                ),
            ],
          ),
        ),
        if (_tab == _LibraryTab.songs && tracks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 3, 30, 0),
            child: SizedBox(
              height: 32,
              child: Row(
                children: [
                  const SizedBox(width: 56),
                  Expanded(
                    flex: 4,
                    child: Text('TITLE', style: _columnLabelStyle),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text('ALBUM', style: _columnLabelStyle),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      'LENGTH',
                      textAlign: TextAlign.end,
                      style: _columnLabelStyle,
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
          ),
        Expanded(
          child: tracks.isEmpty
              ? _emptyLibrary()
              : switch (_tab) {
                  _LibraryTab.songs => _songList(tracks),
                  _LibraryTab.artists => _artistGrid(tracks),
                  _LibraryTab.albums => _albumGrid(tracks),
                },
        ),
      ],
    );
  }

  Widget _emptyLibrary() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.library_music_outlined,
          size: 48,
          color: Color(0xFF8A9693),
        ),
        const SizedBox(height: 12),
        Text(
          _query.isEmpty ? 'Your music will appear here' : 'No matches found',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        if (_query.isEmpty)
          Text(
            'Add a folder to scan your local collection.',
            style: TextStyle(color: _muted),
          ),
        if (_query.isEmpty) const SizedBox(height: 14),
        if (_query.isEmpty)
          FilledButton.icon(
            onPressed: _chooseFolder,
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose music folder'),
          ),
      ],
    ),
  );

  Widget _songList(List<Track> tracks) {
    final groups = <String, List<Track>>{};
    for (final track in tracks) {
      groups.putIfAbsent(_letter(track.title), () => []).add(track);
    }
    final letters = groups.keys.toList()..sort();
    return CustomScrollView(
      slivers: [
        for (final letter in letters) ...[
          SliverPersistentHeader(
            pinned: true,
            delegate: _LetterHeader(
              letter,
              _letterKeys.putIfAbsent(letter, GlobalKey.new),
            ),
          ),
          SliverList.builder(
            itemCount: groups[letter]!.length,
            itemBuilder: (context, index) =>
                _trackRow(groups[letter]![index], tracks),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  Widget _trackRow(Track track, List<Track> queue) => InkWell(
    onTap: () => _play(track, queue: queue),
    hoverColor: _brightness.value == Brightness.dark
        ? const Color(0xFF29272D)
        : const Color(0xFFE9E1F2),
    splashColor: _brightness.value == Brightness.dark
        ? const Color(0x339B72CF)
        : const Color(0x337046A8),
    child: SizedBox(
      height: 61,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Row(
          children: [
            _art(track.artwork, 42),
            const SizedBox(width: 14),
            Expanded(
              flex: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: _ink,
                    ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: _muted),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                track.album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _muted),
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                _duration(track.duration),
                textAlign: TextAlign.end,
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Track options',
              onSelected: (value) async {
                if (value == 'play') await _play(track, queue: queue);
                if (value == 'playlist') await _addToPlaylist(track);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'play', child: Text('Play next')),
                PopupMenuItem(
                  value: 'playlist',
                  child: Text('Add to playlist'),
                ),
              ],
              child: Icon(Icons.more_horiz, color: _muted),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _artistGrid(List<Track> tracks) {
    final artists = <String, Track>{};
    for (final track in tracks) {
      artists.putIfAbsent(track.artist, () => track);
    }
    final entries = artists.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return GridView.builder(
      padding: const EdgeInsets.all(28),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisExtent: 210,
        crossAxisSpacing: 16,
        mainAxisSpacing: 14,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return InkWell(
          onTap: () => setState(() {
            _query = entry.key;
            _tab = _LibraryTab.songs;
          }),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: _art(entry.value.artwork, double.infinity),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                entry.key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${tracks.where((item) => item.artist == entry.key).length} songs',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _albumGrid(List<Track> tracks) {
    final albums = <String, Track>{};
    for (final track in tracks) {
      albums.putIfAbsent('${track.album}\u0000${track.artist}', () => track);
    }
    final entries = albums.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return GridView.builder(
      padding: const EdgeInsets.all(28),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisExtent: 236,
        crossAxisSpacing: 16,
        mainAxisSpacing: 14,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final parts = entry.key.split('\u0000');
        return InkWell(
          onTap: () => setState(() {
            _query = '${parts[0]} ${parts[1]}';
            _tab = _LibraryTab.songs;
          }),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: _art(entry.value.artwork, double.infinity),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                parts[0],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                parts[1],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _playlistPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(30, 4, 30, 16),
        child: Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: _createPlaylist,
              icon: const Icon(Icons.add),
              label: const Text('New playlist'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _importPlaylist,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import M3U'),
            ),
          ],
        ),
      ),
      Expanded(
        child: _playlists.isEmpty
            ? Center(
                child: Text(
                  'No playlists yet',
                  style: TextStyle(color: _muted),
                ),
              )
            : ListView.builder(
                itemCount: _playlists.length,
                itemBuilder: (context, index) {
                  final playlist = _playlists[index];
                  final id = playlist['id']! as int;
                  final name = playlist['name']! as String;
                  final count = playlist['track_count']! as int;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 4,
                    ),
                    leading: Icon(Icons.queue_music, color: _teal),
                    title: Text(name),
                    subtitle: Text('$count tracks'),
                    onTap: () async {
                      final tracks = await widget.database.playlistTracks(id);
                      if (tracks.isNotEmpty) {
                        await _play(tracks.first, queue: tracks);
                      }
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Export playlist',
                          icon: const Icon(Icons.ios_share),
                          onPressed: () async {
                            try {
                              await M3uService(widget.database)
                                  .exportPlaylist(id, name);
                            } on Object catch (error) {
                              if (mounted) {
                                setState(
                                  () => _message =
                                      'Could not export playlist: $error',
                                );
                              }
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Delete playlist',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await widget.database.deletePlaylist(id);
                            await _reload();
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    ],
  );

  Widget _settings() => ListView(
    padding: const EdgeInsets.all(30),
    children: [
      const Text(
        'Music folders',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Light mode'),
        subtitle: const Text('Use a light appearance throughout Echo'),
        value: _brightness.value == Brightness.light,
        onChanged: (light) => _brightness.value =
            light ? Brightness.light : Brightness.dark,
      ),
      const Divider(height: 38),
      const SizedBox(height: 8),
      Text(
        'Echo indexes supported audio files in these folders.',
        style: TextStyle(color: _muted),
      ),
      const SizedBox(height: 18),
      for (final root in _roots)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_outlined),
          title: Text(root, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            tooltip: 'Remove folder',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () async {
              await widget.database.removeRoot(root);
              await _reload();
            },
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _chooseFolder,
          icon: const Icon(Icons.add),
          label: const Text('Add folder'),
        ),
      ),
      const Divider(height: 38),
      const Text(
        'Playback',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.graphic_eq),
        title: Text(
          'Equalizer presets are stored in your local library database',
        ),
      ),
    ],
  );

  Widget _nowPlaying() => ValueListenableBuilder<Track?>(
    valueListenable: widget.audio.currentTrack,
    builder: (context, track, _) => track == null
        ? Stack(
            children: [
              Center(
                child: Text(
                  'Nothing is playing',
                  style: TextStyle(color: _muted),
                ),
              ),
              _nowPlayingBackButton(),
            ],
          )
        : AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            decoration: BoxDecoration(
              color: Color.lerp(_ambientColor, _surface, .35),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (track.artwork != null && track.artwork!.isNotEmpty)
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 44, sigmaY: 44),
                    child: Image.memory(
                      Uint8List.fromList(track.artwork!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => const SizedBox(),
                    ),
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xB3171719), Color(0xD9171719)],
                    ),
                  ),
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: .94, end: 1),
                              duration: const Duration(milliseconds: 460),
                              curve: Curves.easeOutCubic,
                              builder: (context, scale, child) =>
                                  Transform.scale(scale: scale, child: child),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: .38,
                                        ),
                                        blurRadius: 36,
                                        offset: const Offset(0, 18),
                                      ),
                                    ],
                                  ),
                                  child: _art(track.artwork, double.infinity),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 26),
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _ink,
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${track.artist} · ${track.album}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: _muted),
                          ),
                          const SizedBox(height: 20),
                          _transportControls(large: true),
                        ],
                      ),
                    ),
                  ),
                ),
                _nowPlayingBackButton(),
              ],
            ),
          ),
  );

  Widget _nowPlayingBackButton() => Positioned(
    top: 18,
    left: 20,
    child: TextButton.icon(
      onPressed: () => setState(() => _section = _Section.music),
      icon: const Icon(Icons.arrow_back),
      label: const Text('My music'),
      style: TextButton.styleFrom(foregroundColor: _ink),
    ),
  );

  Widget _playerBar() => Container(
    height: 82,
    decoration: BoxDecoration(
      color: _panel,
      border: Border(top: BorderSide(color: _line)),
    ),
    child: Column(
      children: [
        Expanded(
          child: Row(
            children: [
              const SizedBox(width: 18),
              ValueListenableBuilder<Track?>(
                valueListenable: widget.audio.currentTrack,
                builder: (context, track, _) => SizedBox(
                  width: 270,
                  child: track == null
                      ? Text(
                          'Select a song to play',
                          style: TextStyle(color: _muted),
                        )
                      : Row(
                          children: [
                            _art(track.artwork, 48),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const Spacer(),
              _transportControls(),
              const Spacer(),
              IconButton(
                tooltip: 'Now playing',
                onPressed: () => setState(() => _section = _Section.nowPlaying),
                icon: const Icon(Icons.open_in_full, size: 18),
              ),
              ValueListenableBuilder<double>(
                valueListenable: widget.audio.volume,
                builder: (context, value, _) => Row(
                  children: [
                    IconButton(
                      tooltip: value == 0
                          ? 'Unmute app audio'
                          : 'Mute app audio',
                      onPressed: widget.audio.toggleMute,
                      icon: Icon(
                        value == 0 ? Icons.volume_off : Icons.volume_up,
                        size: 19,
                      ),
                    ),
                    SizedBox(
                      width: 122,
                      child: Slider(
                        value: value.clamp(0, 200),
                        min: 0,
                        max: 200,
                        divisions: 40,
                        semanticFormatterCallback: (level) =>
                            'App volume ${level.round()} percent',
                        onChanged: widget.audio.setVolume,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
        ValueListenableBuilder<Duration>(
          valueListenable: widget.audio.duration,
          builder: (context, total, _) => ValueListenableBuilder<Duration>(
            valueListenable: widget.audio.position,
            builder: (context, position, _) => SizedBox(
              height: 4,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  padding: EdgeInsets.zero,
                  min: 0,
                  max: total.inMilliseconds > 0
                      ? total.inMilliseconds.toDouble()
                      : 1,
                  value: position.inMilliseconds
                      .clamp(
                        0,
                        total.inMilliseconds > 0 ? total.inMilliseconds : 1,
                      )
                      .toDouble(),
                  onChanged: total == Duration.zero
                      ? null
                      : (value) => widget.audio.seek(
                          Duration(milliseconds: value.round()),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _transportControls({bool large = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ValueListenableBuilder<bool>(
        valueListenable: widget.audio.shuffle,
        builder: (context, value, _) => IconButton(
          tooltip: 'Shuffle',
          color: value ? _teal : _muted,
          onPressed: widget.audio.toggleShuffle,
          icon: Icon(Icons.shuffle, size: large ? 23 : 18),
        ),
      ),
      IconButton(
        tooltip: 'Previous',
        onPressed: widget.audio.previous,
        icon: Icon(Icons.skip_previous, size: large ? 34 : 24),
      ),
      ValueListenableBuilder<bool>(
        valueListenable: widget.audio.playing,
        builder: (context, playing, _) => IconButton.filled(
          onPressed: widget.audio.togglePlay,
          icon: Icon(
            playing ? Icons.pause : Icons.play_arrow,
            size: large ? 29 : 22,
          ),
        ),
      ),
      IconButton(
        tooltip: 'Next',
        onPressed: widget.audio.next,
        icon: Icon(Icons.skip_next, size: large ? 34 : 24),
      ),
      ValueListenableBuilder(
        valueListenable: widget.audio.repeat,
        builder: (context, mode, _) => IconButton(
          tooltip: switch (mode) {
            PlaylistMode.none => 'Repeat off',
            PlaylistMode.loop => 'Repeat all',
            PlaylistMode.single => 'Repeat one',
          },
          color: mode == PlaylistMode.none ? _muted : _teal,
          onPressed: widget.audio.cycleRepeat,
          icon: Icon(
            mode == PlaylistMode.single ? Icons.repeat_one : Icons.repeat,
            size: large ? 22 : 18,
          ),
        ),
      ),
    ],
  );

  Future<void> _showJumpGrid() async {
    final letters = _visibleTracks.map((track) => _letter(track.title)).toSet();
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Jump to'),
        content: SizedBox(
          width: 380,
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final letter in [
                '#',
                ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''),
              ])
                SizedBox(
                  width: 42,
                  child: TextButton(
                    onPressed: letters.contains(letter)
                        ? () => Navigator.pop(context, letter)
                        : null,
                    child: Text(letter),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final contextForLetter = _letterKeys[selected]?.currentContext;
    if (contextForLetter != null && contextForLetter.mounted) {
      await Scrollable.ensureVisible(
        contextForLetter,
        duration: const Duration(milliseconds: 240),
      );
    }
  }

  final Map<String, GlobalKey> _letterKeys = {};

  Future<void> _addToPlaylist(Track track) async {
    if (_playlists.isEmpty) {
      await _createPlaylist();
      await _reload();
    }
    if (_playlists.isEmpty || !mounted) return;
    final selectedId = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add to playlist'),
        children: [
          for (final playlist in _playlists)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, playlist['id']! as int),
              child: Text(playlist['name']! as String),
            ),
        ],
      ),
    );
    if (selectedId != null) {
      await widget.database.addToPlaylist(selectedId, track.id);
    }
    await _reload();
  }

  String _letter(String title) {
    final first = title.trim().isEmpty ? '#' : title.trim()[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(first) ? first : '#';
  }

  Widget _art(List<int>? bytes, double size) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: SizedBox(
      width: size,
      height: size,
      child: bytes == null || bytes.isEmpty
          ? Container(
              color: const Color(0xFF343238),
              child: Icon(Icons.music_note, color: _teal),
            )
          : Image.memory(
              Uint8List.fromList(bytes),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Container(
                color: const Color(0xFF343238),
                child: Icon(Icons.music_note, color: _teal),
              ),
            ),
    ),
  );

  String _duration(Duration duration) =>
      '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _LetterHeader extends SliverPersistentHeaderDelegate {
  _LetterHeader(this.letter, this.key);
  final String letter;
  final GlobalKey key;

  @override
  double get minExtent => 38;
  @override
  double get maxExtent => 38;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Container(
    key: key,
    alignment: Alignment.centerLeft,
    color: _surface,
    padding: const EdgeInsets.only(left: 34),
    child: Text(
      letter,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: _teal,
      ),
    ),
  );
  @override
  bool shouldRebuild(covariant _LetterHeader oldDelegate) =>
      letter != oldDelegate.letter;
}

int _extractDominantColor(Uint8List bytes) {
  final decoded = image.decodeImage(bytes);
  if (decoded == null) return 0xFF173B3B;
  final sample = image.copyResize(decoded, width: 24, height: 24);
  var red = 0;
  var green = 0;
  var blue = 0;
  for (var y = 0; y < sample.height; y++) {
    for (var x = 0; x < sample.width; x++) {
      final pixel = sample.getPixel(x, y);
      red += pixel.r.toInt();
      green += pixel.g.toInt();
      blue += pixel.b.toInt();
    }
  }
  const samples = 24 * 24;
  final averageRed = red ~/ samples;
  final averageGreen = green ~/ samples;
  final averageBlue = blue ~/ samples;
  final channelRange =
      [
        averageRed,
        averageGreen,
        averageBlue,
      ].reduce((first, second) => first > second ? first : second) -
      [
        averageRed,
        averageGreen,
        averageBlue,
      ].reduce((first, second) => first < second ? first : second);
  if (channelRange < 22) return 0xFF285653;
  return 0xFF000000 | (averageRed << 16) | (averageGreen << 8) | averageBlue;
}
