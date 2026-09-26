#!/usr/bin/env sh
set -eu

command -v flutter >/dev/null 2>&1 || { printf '%s\n' 'Flutter is required on PATH.' >&2; exit 1; }
command -v cmake >/dev/null 2>&1 || { printf '%s\n' 'CMake is required on PATH.' >&2; exit 1; }
command -v ninja >/dev/null 2>&1 || { printf '%s\n' 'Ninja is required on PATH.' >&2; exit 1; }

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
flutter pub get
flutter build linux --release

APP_DIR="$ROOT/build/linux/x64/release/bundle"
install -Dm644 packaging/org.echo.Echo.desktop "$APP_DIR/share/applications/org.echo.Echo.desktop"
install -Dm644 packaging/org.echo.Echo.metainfo.xml "$APP_DIR/share/metainfo/org.echo.Echo.metainfo.xml"
install -Dm644 packaging/icons/org.echo.Echo.svg "$APP_DIR/share/icons/hicolor/scalable/apps/org.echo.Echo.svg"
printf 'Release bundle: %s\n' "$APP_DIR"
