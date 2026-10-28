#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
VERSION=${1:-$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$ROOT/Cargo.toml" | head -n 1)}
ARCH=${2:-$(dpkg --print-architecture)}
PACKAGE_NAME=codex-plus-plus
OUT="$ROOT/dist/linux"
BINARY_DIR=${BINARY_DIR:-$ROOT/target/release}
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/codex-plus-plus-deb.XXXXXX")
# mktemp 默认 0700；包内根目录须可遍历。
chmod 0755 "$STAGE"

test -n "$VERSION"
test -x "$BINARY_DIR/codex-plus-plus"
command -v dpkg-deb >/dev/null
command -v dpkg-shlibdeps >/dev/null
command -v readelf >/dev/null
if [ "$ARCH" != amd64 ]; then
  printf 'error: this fork only packages amd64, got %s\n' "$ARCH" >&2
  exit 1
fi

# 在旧版 glibc 上构建，并在打包时守住兼容基线。
GLIBC_REQUIRED=$(readelf --version-info "$BINARY_DIR/codex-plus-plus" | grep -oE 'GLIBC_[0-9]+(\.[0-9]+)+' | sort -Vu | tail -n 1)
GLIBC_REQUIRED=${GLIBC_REQUIRED#GLIBC_}
if dpkg --compare-versions "$GLIBC_REQUIRED" gt 2.36; then
  printf 'error: binary requires glibc %s; build on Debian bookworm (<= 2.36)\n' "$GLIBC_REQUIRED" >&2
  exit 1
fi

mkdir -p \
  "$STAGE/DEBIAN" \
  "$STAGE/usr/bin" \
  "$STAGE/usr/lib/$PACKAGE_NAME" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/icons/hicolor/256x256/apps"

install -m 0755 "$BINARY_DIR/codex-plus-plus" \
  "$STAGE/usr/lib/$PACKAGE_NAME/codex-plus-plus"
install -m 0644 "$ROOT/apps/codex-plus-manager/src-tauri/icons/icon.png" \
  "$STAGE/usr/share/icons/hicolor/256x256/apps/codex-plus-plus.png"

ln -s "/usr/lib/$PACKAGE_NAME/codex-plus-plus" "$STAGE/usr/bin/codex-plus-plus"
# 旧命令仍可打开新版统一界面，但不携带 target 中可能残留的旧二进制。
ln -s codex-plus-plus "$STAGE/usr/lib/$PACKAGE_NAME/codex-plus-plus-manager"
ln -s "/usr/lib/$PACKAGE_NAME/codex-plus-plus" "$STAGE/usr/bin/codex-plus-plus-manager"

# 根据实际 ELF 生成运行库依赖，避免 glibc / libstdc++ 版本漏报。
META=$(mktemp -d "${TMPDIR:-/tmp}/codex-plus-plus-shlibs.XXXXXX")
mkdir -p "$META/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: %s\nDescription: Codex++\n' \
  "$PACKAGE_NAME" "$PACKAGE_NAME" "$ARCH" > "$META/debian/control"
SHLIB_DEPENDS=$(cd "$META" && dpkg-shlibdeps -O -e"$STAGE/usr/lib/$PACKAGE_NAME/codex-plus-plus")
SHLIB_DEPENDS=${SHLIB_DEPENDS#shlibs:Depends=}

cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PACKAGE_NAME
Version: $VERSION
Section: devel
Priority: optional
Architecture: $ARCH
Maintainer: Codex++ contributors
Depends: $SHLIB_DEPENDS, libgtk-3-0, libwebkit2gtk-4.1-0, libayatana-appindicator3-1, librsvg2-2
Description: Codex++ unified management application
 Configure providers, models, sessions and launch the official Codex desktop app.
EOF

cat > "$STAGE/usr/share/applications/codex-plus-plus.desktop" <<'EOF'
[Desktop Entry]
Name=Codex++
Comment=Configure and launch Codex++
Exec=/usr/bin/codex-plus-plus %u
Icon=codex-plus-plus
Terminal=false
Type=Application
Categories=Development;Utility;
StartupNotify=true
MimeType=x-scheme-handler/codexplusplus;x-scheme-handler/dreamskin;
EOF

mkdir -p "$OUT"
dpkg-deb --build --root-owner-group "$STAGE" "$OUT/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"
printf 'created %s\n' "$OUT/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"
