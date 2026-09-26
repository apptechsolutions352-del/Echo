# Echo

Echo is a Linux desktop music library and player built with Flutter, SQLite, and libmpv through media_kit.

## Build and install

Prerequisites: Flutter with Linux desktop enabled, CMake, Ninja, GTK 3 development headers, and network access for Flutter/native asset downloads.

```sh
flutter pub get
flutter test
flutter analyze
./packaging/build-linux.sh
```

The release bundle is written to `build/linux/x64/release/bundle`. Install it under `/usr/local` with:

```sh
./packaging/install-linux.sh
```

Pass an alternate installation prefix as the first argument. The packaging directory contains the desktop entry, AppStream metadata, application icon, build helper, and install helper. Debian users can validate metadata with `desktop-file-validate` and `appstreamcli validate`.

## Library data

The SQLite catalog lives under the platform application support directory in `echo-library.sqlite3`. It stores normalized artists, albums, tracks, root folders, playlists, settings, and equalizer preset records. Scans recurse through selected folders, retain filename-derived titles when metadata is unreadable, use embedded or folder artwork, and reconcile removed paths. Directory changes are monitored through Linux filesystem watchers.

The library view supports title/artist/album/year/genre sorting, search, folder filtering, artist and album groupings, and alphabetical navigation. Playlists support local CRUD and M3U/M3U8 import/export. Audio can also be opened from the desktop entry or dropped into the app.

## Current integration boundary

The player uses libmpv via media_kit and supports queue transport, seeking, shuffle, repeat, and volume. Output-device errors are surfaced in the UI. This initial release does not implement MPRIS2 D-Bus registration, a DSP equalizer pipeline, crossfade, or a release homepage URL; do not advertise those integrations until they are implemented and tested. The AppStream homepage URL must be set to the project's real published URL before distribution.
