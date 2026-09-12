#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
VERSION=${1:-$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$ROOT/Cargo.toml" | head -n 1)}
ARCH=${2:-$(dpkg --print-architecture)}
PACKAGE_NAME=codex-plus-plus
OUT="$ROOT/dist/linux"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/codex-plus-plus-deb.XXXXXX")

test -n "$VERSION"
test -x "$ROOT/target/release/codex-plus-plus"
test -x "$ROOT/target/release/codex-plus-plus-manager"
command -v dpkg-deb >/dev/null

mkdir -p \
  "$STAGE/DEBIAN" \
  "$STAGE/usr/bin" \
  "$STAGE/usr/lib/$PACKAGE_NAME" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/icons/hicolor/256x256/apps"

install -m 0755 "$ROOT/target/release/codex-plus-plus" \
  "$STAGE/usr/lib/$PACKAGE_NAME/codex-plus-plus"
install -m 0755 "$ROOT/target/release/codex-plus-plus-manager" \
  "$STAGE/usr/lib/$PACKAGE_NAME/codex-plus-plus-manager"
install -m 0644 "$ROOT/assets/images/codex-plus-plus.png" \
  "$STAGE/usr/share/icons/hicolor/256x256/apps/codex-plus-plus.png"

ln -s "/usr/lib/$PACKAGE_NAME/codex-plus-plus" "$STAGE/usr/bin/codex-plus-plus"
ln -s "/usr/lib/$PACKAGE_NAME/codex-plus-plus-manager" "$STAGE/usr/bin/codex-plus-plus-manager"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PACKAGE_NAME
Version: $VERSION
Section: devel
Priority: optional
Architecture: $ARCH
Maintainer: Codex++ contributors
Depends: libgtk-3-0, libwebkit2gtk-4.1-0, libayatana-appindicator3-1, librsvg2-2
Description: Codex++ launcher and management tool
 External launcher and manager for the OpenAI Codex desktop application.
EOF

cat > "$STAGE/usr/share/applications/codex-plus-plus.desktop" <<'EOF'
[Desktop Entry]
Name=Codex++
Comment=Launch Codex++
Exec=/usr/lib/codex-plus-plus/codex-plus-plus
Icon=codex-plus-plus
Terminal=false
Type=Application
Categories=Development;Utility;
EOF

cat > "$STAGE/usr/share/applications/codex-plus-plus-manager.desktop" <<'EOF'
[Desktop Entry]
Name=Codex++ 管理工具
Comment=Manage Codex++ providers and settings
Exec=/usr/lib/codex-plus-plus/codex-plus-plus-manager
Icon=codex-plus-plus
Terminal=false
Type=Application
Categories=Development;Utility;
EOF

mkdir -p "$OUT"
dpkg-deb --build --root-owner-group "$STAGE" "$OUT/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"
printf 'created %s\n' "$OUT/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"
