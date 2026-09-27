# Echo

Echo is a Linux desktop music library and player built with Flutter, SQLite, and libmpv through media_kit.

## Author and license

Author and maintainer: Manasseh Sasu <apptechsolutions352@gmail.com>.

License: Proprietary. All rights reserved.

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

Build a Debian/Ubuntu amd64 installer from the release bundle with:

```sh
./packaging/build-deb.sh
```

The package is written to `build/packages/echo_0.1.1_amd64.deb`. Pass a version as the first argument to change it. Users can install the package with `sudo apt install ./echo_0.1.1_amd64.deb`.

## Library data

The SQLite catalog lives under the platform application support directory in `echo-library.sqlite3`. It stores normalized artists, albums, tracks, root folders, playlists, settings, and equalizer preset records. Scans recurse through selected folders, retain filename-derived titles when metadata is unreadable, use embedded or folder artwork, and reconcile removed paths. Directory changes are monitored through Linux filesystem watchers.

The library view supports title/artist/album/year/genre sorting, search, folder filtering, artist and album groupings, and alphabetical navigation. Playlists support local CRUD and M3U/M3U8 import/export. Audio can also be opened from the desktop entry or dropped into the app.

## Anonymous install count

On the first launch for a local app data installation, Echo makes one empty-body `POST` to `https://echo-2ve.pages.dev/api/install`. A local SQLite setting prevents later launches from sending it again; reinstalling or deleting Echo's local data may count as a new install. The event counts accepted first-launch reports, not verified unique people, devices, downloads, or website visits. There is no retry: if the endpoint is unavailable or the app is offline on first launch, that install may not be counted. Analytics is best effort and does not block the app. Echo sends no names, email addresses, device identifiers, or analytics payload. Cloudflare processes connection metadata, including the source IP address, to handle the request.

## Current integration boundary

The player uses libmpv via media_kit and supports queue transport, seeking, shuffle, repeat, and volume. On Linux, playback state and controls are exposed through MPRIS2 over D-Bus. Output-device errors are surfaced in the UI. A DSP equalizer pipeline and crossfade are not implemented. The AppStream metadata points to the published project homepage.
