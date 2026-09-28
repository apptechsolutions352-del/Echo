#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUNDLE="$ROOT/build/linux/x64/release/bundle"
VERSION=${1:-0.1.1}
ARCH=$(dpkg --print-architecture)
OUTPUT_DIR="$ROOT/build/packages"
OUTPUT="$OUTPUT_DIR/echo_${VERSION}_${ARCH}.deb"

if [ ! -x "$BUNDLE/echo" ]; then
  printf '%s\n' 'Linux release bundle is missing. Run packaging/build-linux.sh first.' >&2
  exit 1
fi

command -v dpkg-deb >/dev/null 2>&1 || {
  printf '%s\n' 'dpkg-deb is required to build Debian packages.' >&2
  exit 1
}

mkdir -p "$OUTPUT_DIR"
STAGE=$(mktemp -d "$OUTPUT_DIR/echo-deb.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT HUP INT TERM
chmod 755 "$STAGE"

install -d "$STAGE/opt/echo" \
  "$STAGE/usr/bin" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/icons/hicolor/scalable/apps" \
  "$STAGE/usr/share/metainfo" \
  "$STAGE/DEBIAN"

cp -a "$BUNDLE/." "$STAGE/opt/echo/"
ln -s /opt/echo/echo "$STAGE/usr/bin/echo-player"
install -m 644 "$ROOT/packaging/org.echo.Echo.desktop" \
  "$STAGE/usr/share/applications/org.echo.Echo.desktop"
install -m 644 "$ROOT/packaging/icons/org.echo.Echo.svg" \
  "$STAGE/usr/share/icons/hicolor/scalable/apps/org.echo.Echo.svg"
install -m 644 "$ROOT/packaging/org.echo.Echo.metainfo.xml" \
  "$STAGE/usr/share/metainfo/org.echo.Echo.metainfo.xml"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: echo
Version: $VERSION
Section: sound
Priority: optional
Architecture: $ARCH
Depends: libc6, libgtk-3-0 | libgtk-3-0t64, libglib2.0-0 | libglib2.0-0t64, libmpv2 | libmpv2t64, libstdc++6
Maintainer: Manasseh Sasu <apptechsolutions352@gmail.com>
Homepage: https://echo-2ve.pages.dev
Description: Linux desktop music library and player
 Echo indexes local music folders, manages playlists, and plays audio.
EOF

dpkg-deb --root-owner-group --build "$STAGE" "$OUTPUT"
printf 'Debian package: %s\n' "$OUTPUT"
