#!/usr/bin/env bash
# Copyright (c) 2026 Chris Coetzee
# SPDX-License-Identifier: MIT
# The full license text is in LICENSE at the repository root.
#
# Deterministic Linux x64 packager (pure-Dart usbfs build) producing:
#   - .tar.gz portable archive
#   - .deb Debian/Ubuntu package (with udev rule + postinst reload)
#   - .rpm Fedora/RHEL/openSUSE package (with udev rule + %post reload)
#   - .AppImage portable Linux bundle (via appimagetool --appimage-extract-and-run)
#   - SHA256SUMS.txt

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=""
OUT_DIR="$ROOT/dist"
FORMATS="tar,deb,rpm,appimage"
SKIP_BUILD=0
DRY_RUN=0
DEBUG=0
APPIMAGETOOL=""

usage() {
  cat <<'EOF'
Usage: tool/package_linux.sh [options]

Builds the Linux x64 pure-Dart usbfs Flutter release bundle, audits its
shared-library dependencies, and packages requested Linux artifacts plus
SHA256SUMS.txt.

Options:
  --version VER           Release version (X.Y.Z). Defaults to pubspec.yaml.
  --out-dir DIR           Output directory for packages (default: ./dist).
  --formats LIST          Comma-separated list: tar,deb,rpm,appimage (default: all).
  --skip-build            Reuse existing build/linux/x64/release/bundle.
  --appimagetool PATH     Path to appimagetool binary (auto-detected if on PATH).
  --dry-run               Print planned steps without building or writing files.
  --debug                 Print every executed command prefixed with "+ ".
  -h, --help              Show this help and exit.

Environment:
  APPIMAGETOOL            Alternative way to specify appimagetool path.
  FLUTTER_BIN             Flutter executable to use (default: flutter).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2#v}"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --formats) FORMATS="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --appimagetool) APPIMAGETOOL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --debug) DEBUG=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

FLUTTER="${FLUTTER_BIN:-flutter}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(sed -nE 's/^version:[[:space:]]*([^[:space:]+#]+).*/\1/p' "$ROOT/pubspec.yaml" | head -n1)"
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]]; then
  echo "Invalid version: '$VERSION'" >&2
  exit 2
fi

run() {
  if [[ "$DEBUG" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
    printf '+ %q' "$1" >&2
    shift || true
    for arg in "$@"; do printf ' %q' "$arg" >&2; done
    printf '\n' >&2
    return 0
  fi
  "$@"
}

exec_cmd() {
  if [[ "$DEBUG" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
    printf '+ ' >&2
    printf '%q ' "$@" >&2
    printf '\n' >&2
  fi
  if [[ "$DRY_RUN" -eq 0 ]]; then
    "$@"
  fi
}

has_format() {
  [[ ",$FORMATS," == *",$1,"* ]]
}

BUNDLE="$ROOT/build/linux/x64/release/bundle"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  echo "==> Building Flutter Linux release (pure-Dart usbfs)"
  (
    cd "$ROOT"
    exec_cmd "$FLUTTER" build linux --release
  )
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  if [[ ! -x "$BUNDLE/dji_mic_control" ]]; then
    echo "Release binary missing at $BUNDLE/dji_mic_control" >&2
    exit 1
  fi
  echo "==> Auditing shared-library dependencies (readelf -d)"
  NEEDED="$(readelf -d "$BUNDLE/dji_mic_control" | grep '(NEEDED)' || true)"
  echo "$NEEDED"
  if echo "$NEEDED" | grep -qiE 'appindicator|ayatana|libnotify|libusb|webkit'; then
    echo "ERROR: unexpected OS-specific library linked into dji_mic_control" >&2
    exit 1
  fi
fi

exec_cmd mkdir -p "$OUT_DIR"
WORK=""
cleanup() {
  if [[ -n "$WORK" && -d "$WORK" ]]; then
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT
if [[ "$DRY_RUN" -eq 0 ]]; then
  WORK="$(mktemp -d)"
else
  WORK="/tmp/dji-mic-control-pkg-dry-run"
fi

# 1. Portable .tar.gz archive
if has_format tar; then
  TAR_NAME="dji-mic-control-v${VERSION}-linux-x64.tar.gz"
  STAGE="$WORK/tar/dji-mic-control-v${VERSION}-linux-x64"
  echo "==> Packaging $TAR_NAME"
  exec_cmd mkdir -p "$STAGE"
  exec_cmd cp -a "$BUNDLE/." "$STAGE/"
  exec_cmd cp "$ROOT/packaging/60-dji-mic.rules" "$STAGE/"
  exec_cmd cp "$ROOT/packaging/dji-mic-control.desktop" "$STAGE/"
  exec_cmd cp "$ROOT/LICENSE" "$ROOT/README.md" "$ROOT/CHANGELOG.md" "$STAGE/"
  exec_cmd tar -C "$WORK/tar" -czf "$OUT_DIR/$TAR_NAME" "dji-mic-control-v${VERSION}-linux-x64"
fi

# 2. Debian/Ubuntu .deb package
if has_format deb; then
  DEB_NAME="dji-mic-control_${VERSION}_amd64.deb"
  DEB_ROOT="$WORK/deb/pkg"
  echo "==> Packaging $DEB_NAME"
  exec_cmd mkdir -p \
    "$DEB_ROOT/DEBIAN" \
    "$DEB_ROOT/opt/dji-mic-control" \
    "$DEB_ROOT/usr/bin" \
    "$DEB_ROOT/usr/share/applications" \
    "$DEB_ROOT/usr/share/icons/hicolor/128x128/apps" \
    "$DEB_ROOT/etc/udev/rules.d" \
    "$DEB_ROOT/usr/share/doc/dji-mic-control"

  exec_cmd cp -a "$BUNDLE/." "$DEB_ROOT/opt/dji-mic-control/"
  exec_cmd ln -sf "/opt/dji-mic-control/dji_mic_control" "$DEB_ROOT/usr/bin/dji-mic-control"
  exec_cmd cp "$ROOT/packaging/dji-mic-control.desktop" "$DEB_ROOT/usr/share/applications/dji-mic-control.desktop"
  exec_cmd cp "$ROOT/assets/icons/app-icon.png" "$DEB_ROOT/usr/share/icons/hicolor/128x128/apps/dji-mic-control.png"
  exec_cmd cp "$ROOT/packaging/60-dji-mic.rules" "$DEB_ROOT/etc/udev/rules.d/60-dji-mic.rules"
  exec_cmd cp "$ROOT/LICENSE" "$DEB_ROOT/usr/share/doc/dji-mic-control/copyright"

  if [[ "$DRY_RUN" -eq 0 ]]; then
    INSTALLED_KB="$(du -sk "$DEB_ROOT/opt" "$DEB_ROOT/usr" | awk '{s+=$1} END {print s}')"
    cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: dji-mic-control
Version: ${VERSION}
Section: sound
Priority: optional
Architecture: amd64
Installed-Size: ${INSTALLED_KB}
Depends: libgtk-3-0t64 | libgtk-3-0, libglib2.0-0t64 | libglib2.0-0, libepoxy0, libfontconfig1
Maintainer: Chris Coetzee <chriscz93@gmail.com>
Homepage: https://github.com/chriscz/dji-mic-control
Description: Desktop controller for DJI wireless microphones
 Linux-first Flutter desktop controller for DJI Mic Mini, DJI Mic Mini 2
 transmitters, and DJI Mic Series Mobile Receiver over USB Interface 6.
EOF
    cat > "$DEB_ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload-rules || true
  udevadm trigger --action=add --subsystem-match=usb --attr-match=idVendor=2ca3 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
EOF
    cat > "$DEB_ROOT/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload-rules || true
fi
EOF
    chmod 0755 "$DEB_ROOT/DEBIAN/postinst" "$DEB_ROOT/DEBIAN/postrm"
  fi
  exec_cmd dpkg-deb --root-owner-group --build "$DEB_ROOT" "$OUT_DIR/$DEB_NAME"
fi

# 3. Fedora/RHEL/openSUSE .rpm package
if has_format rpm; then
  RPM_VERSION="${VERSION//-/.}"
  RPM_TOP="$WORK/rpm"
  echo "==> Packaging dji-mic-control-${RPM_VERSION}-1.x86_64.rpm"
  exec_cmd mkdir -p "$RPM_TOP/BUILD" "$RPM_TOP/RPMS" "$RPM_TOP/SOURCES" "$RPM_TOP/SPECS" "$RPM_TOP/SRPMS"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    cat > "$RPM_TOP/SPECS/dji-mic-control.spec" <<EOF
Name:           dji-mic-control
Version:        ${RPM_VERSION}
Release:        1
Summary:        Desktop controller for DJI wireless microphones
License:        MIT
URL:            https://github.com/chriscz/dji-mic-control
Requires:       gtk3
AutoReqProv:    no
%define _build_id_links none

%description
Linux-first Flutter desktop controller for DJI Mic Mini, DJI Mic Mini 2
transmitters, and DJI Mic Series Mobile Receiver over USB Interface 6.

%install
mkdir -p %{buildroot}/opt/dji-mic-control
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/128x128/apps
mkdir -p %{buildroot}/etc/udev/rules.d
mkdir -p %{buildroot}/usr/share/licenses/dji-mic-control
cp -a "${BUNDLE}/." %{buildroot}/opt/dji-mic-control/
ln -sf /opt/dji-mic-control/dji_mic_control %{buildroot}/usr/bin/dji-mic-control
cp "${ROOT}/packaging/dji-mic-control.desktop" %{buildroot}/usr/share/applications/dji-mic-control.desktop
cp "${ROOT}/assets/icons/app-icon.png" %{buildroot}/usr/share/icons/hicolor/128x128/apps/dji-mic-control.png
cp "${ROOT}/packaging/60-dji-mic.rules" %{buildroot}/etc/udev/rules.d/60-dji-mic.rules
cp "${ROOT}/LICENSE" %{buildroot}/usr/share/licenses/dji-mic-control/LICENSE

%post
if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload-rules || true
  udevadm trigger --action=add --subsystem-match=usb --attr-match=idVendor=2ca3 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi

%postun
if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload-rules || true
fi

%files
/opt/dji-mic-control
/usr/bin/dji-mic-control
/usr/share/applications/dji-mic-control.desktop
/usr/share/icons/hicolor/128x128/apps/dji-mic-control.png
%config(noreplace) /etc/udev/rules.d/60-dji-mic.rules
%license /usr/share/licenses/dji-mic-control/LICENSE
EOF
  fi
  exec_cmd rpmbuild --define "_topdir $RPM_TOP" -bb "$RPM_TOP/SPECS/dji-mic-control.spec"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    RPM_BUILT="$(find "$RPM_TOP/RPMS" -name '*.rpm' | head -n1)"
    cp "$RPM_BUILT" "$OUT_DIR/dji-mic-control-${RPM_VERSION}-1.x86_64.rpm"
  fi
fi

# 4. Portable Linux .AppImage
if has_format appimage; then
  APPIMAGE_NAME="dji-mic-control-v${VERSION}-x86_64.AppImage"
  APPDIR="$WORK/AppDir"
  echo "==> Packaging $APPIMAGE_NAME"
  TOOL="${APPIMAGETOOL:-${APPIMAGETOOL_BIN:-$(command -v appimagetool || true)}}"
  if [[ "$DRY_RUN" -eq 0 && -z "$TOOL" ]]; then
    echo "ERROR: appimagetool not found. Install it or pass --appimagetool PATH." >&2
    exit 1
  fi
  exec_cmd mkdir -p \
    "$APPDIR/usr/lib/dji-mic-control" \
    "$APPDIR/usr/share/dji-mic-control" \
    "$APPDIR/usr/share/icons/hicolor/128x128/apps"
  exec_cmd cp -a "$BUNDLE/." "$APPDIR/usr/lib/dji-mic-control/"
  exec_cmd cp "$ROOT/packaging/60-dji-mic.rules" "$APPDIR/usr/share/dji-mic-control/60-dji-mic.rules"
  exec_cmd cp "$ROOT/packaging/dji-mic-control.desktop" "$APPDIR/dji-mic-control.desktop"
  exec_cmd cp "$ROOT/assets/icons/app-icon.png" "$APPDIR/dji-mic-control.png"
  exec_cmd cp "$ROOT/assets/icons/app-icon.png" "$APPDIR/usr/share/icons/hicolor/128x128/apps/dji-mic-control.png"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/dji-mic-control/dji_mic_control" "$@"
EOF
    chmod 0755 "$APPDIR/AppRun"
    ARCH=x86_64 "$TOOL" --appimage-extract-and-run "$APPDIR" "$OUT_DIR/$APPIMAGE_NAME"
  else
    printf '+ ARCH=x86_64 %s --appimage-extract-and-run %s %s\n' "${TOOL:-appimagetool}" "$APPDIR" "$OUT_DIR/$APPIMAGE_NAME" >&2
  fi
fi

# 5. SHA256SUMS.txt
echo "==> Generating SHA256SUMS.txt"
if [[ "$DRY_RUN" -eq 0 ]]; then
  (
    cd "$OUT_DIR"
    rm -f SHA256SUMS.txt
    sha256sum dji-mic-control* > SHA256SUMS.txt
    cat SHA256SUMS.txt
  )
else
  printf '+ (cd %q && sha256sum dji-mic-control* > SHA256SUMS.txt)\n' "$OUT_DIR" >&2
fi
