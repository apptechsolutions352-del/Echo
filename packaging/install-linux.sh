#!/usr/bin/env sh
set -eu

PREFIX=${1:-/usr/local}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$ROOT/build/linux/x64/release/bundle"

if [ ! -x "$APP_DIR/echo" ]; then
  printf '%s\n' 'Release bundle is missing. Run packaging/build-linux.sh first.' >&2
  exit 1
fi

install -d "$PREFIX/lib/echo" "$PREFIX/bin"
cp -a "$APP_DIR/." "$PREFIX/lib/echo/"
ln -sfn "$PREFIX/lib/echo/echo" "$PREFIX/bin/echo-player"
install -Dm644 "$ROOT/packaging/org.echo.Echo.desktop" "$PREFIX/share/applications/org.echo.Echo.desktop"
install -Dm644 "$ROOT/packaging/org.echo.Echo.metainfo.xml" "$PREFIX/share/metainfo/org.echo.Echo.metainfo.xml"
install -Dm644 "$ROOT/packaging/icons/org.echo.Echo.svg" "$PREFIX/share/icons/hicolor/scalable/apps/org.echo.Echo.svg"
