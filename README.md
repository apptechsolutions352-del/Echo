# Echo

Echo is a Linux desktop music library and player built with Flutter, SQLite, and libmpv through media_kit.

## Author and license

Author and maintainer: Manasseh Sasu <apptechsolutions352@gmail.com>.

License: Proprietary. All rights reserved.

## Build and install

Prerequisites: Flutter with Linux desktop enabled, CMake, Ninja, GTK 3 development headers, libmpv, and network access for Flutter/native asset downloads.

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

Build a Debian/Ubuntu amd64 installer from the release bundle with. The package declares GTK, GLib, and libmpv runtime dependencies:

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

## Streaming provider integrations

`lib/services/streaming_provider.dart` defines the provider adapter API. A service integration implements `StreamingProvider` for its own authorization flow, catalog search, and playback URL resolution, then registers the adapter in `StreamingProviderRegistry`. Call `AudioController.playStreamingTrack(provider, result)` to resolve the result immediately before playback; this supports services that issue expiring stream URLs. Remote results are played through the existing media_kit/libmpv player and are not added to the local SQLite catalog.

There is no single API or authentication flow shared by all streaming services. The adapter is the extension point; it does not include credentials or a built-in integration for any particular commercial service. Providers can enforce account, subscription, regional, and playback restrictions in their own implementation.

## Streaming service accounts and playlists

The UI-facing integration is `StreamingService`; providers return `UnifiedPlaylist` values, and `StreamingManager` aggregates them. `SpotifyService` uses Spotify's Web API through the Dart `spotify` package with PKCE and a temporary loopback callback server on `127.0.0.1:8080`. In the Spotify developer dashboard, register exactly `http://127.0.0.1:8080/callback`. Launch Echo with the public client ID, for example:

```sh
flutter run -d linux --dart-define=SPOTIFY_CLIENT_ID=your_client_id
```

For release builds, pass the same Dart define to the build command. The client ID is public; never put a Spotify client secret in the desktop app. Spotify connection currently exists only in memory for the current run. Persisting sessions needs OS keyring storage for the PKCE credentials and verifier. `AppleMusicService` is an intentionally disconnected blueprint: a production implementation needs a backend to sign developer tokens and an Apple Music user authorization flow. The settings UI uses `StreamingConnectionsPanel(manager: manager)` and shows playlists polymorphically.

This layer reads playlist metadata; it does not provide licensed full-track playback. Each platform has separate API and playback terms. Before releasing a provider, follow its attribution requirements for cover art and metadata and confirm that its API access is approved for Echo's distribution model.
