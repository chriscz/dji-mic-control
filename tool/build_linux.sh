#!/usr/bin/env bash
# Copyright (c) 2026 Chris Coetzee
# SPDX-License-Identifier: MIT
# The full license text is in LICENSE at the repository root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-/home/chris.guest/sdk/flutter/bin/flutter}"
if ! [ -x "${FLUTTER_BIN}" ]; then
  FLUTTER_BIN="$(command -v flutter || true)"
fi

DEBUG=0
DRY_RUN=0
WITH_NUSB=0

usage() {
  cat <<'EOF'
Usage: tool/build_linux.sh [options]

Builds the Linux release bundle for apps/dji-mic-control and audits its
shared-library dependencies with ldd.

Options:
  --with-nusb  Also build native/dji_mic_usb/libdji_mic_usb.so and bundle it
  --debug      Print each underlying command prefixed with '+ ' to stderr
  --dry-run    Print planned commands without executing them
  --help       Show this help text

Environment:
  FLUTTER_BIN  Path to flutter executable (default: /home/chris.guest/sdk/flutter/bin/flutter)
  CARGO_BIN    Path to cargo executable (used only with --with-nusb)
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --debug)
      DEBUG=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --with-nusb)
      WITH_NUSB=1
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

run_cmd() {
  if [ "${DEBUG}" -eq 1 ] || [ "${DRY_RUN}" -eq 1 ]; then
    printf '+ %s\n' "$*" >&2
  fi
  if [ "${DRY_RUN}" -eq 0 ]; then
    "$@"
  fi
}

check_prereqs() {
  local missing=()
  [ -n "${FLUTTER_BIN}" ] && [ -x "${FLUTTER_BIN}" ] || missing+=("flutter")
  command -v clang++ >/dev/null 2>&1 || missing+=("clang++ (apt install clang)")
  command -v cmake >/dev/null 2>&1 || missing+=("cmake (apt install cmake)")
  command -v ninja >/dev/null 2>&1 || missing+=("ninja (apt install ninja-build)")
  pkg-config --exists gtk+-3.0 2>/dev/null || missing+=("gtk+-3.0 (apt install libgtk-3-dev)")

  if [ "${#missing[@]}" -gt 0 ]; then
    printf 'Missing Linux build prerequisites:\n' >&2
    for item in "${missing[@]}"; do
      printf '  - %s\n' "${item}" >&2
    done
    if [ "${DRY_RUN}" -eq 0 ]; then
      exit 1
    fi
  fi
}

check_prereqs

run_cmd env -C "${APP_DIR}" "${FLUTTER_BIN}" analyze
run_cmd env -C "${APP_DIR}" "${FLUTTER_BIN}" test
run_cmd env -C "${APP_DIR}" "${FLUTTER_BIN}" build linux --release

BUNDLE_DIR="${APP_DIR}/build/linux/x64/release/bundle"

if [ "${WITH_NUSB}" -eq 1 ]; then
  CARGO_BIN="${CARGO_BIN:-$(command -v cargo || true)}"
  if [ -z "${CARGO_BIN}" ]; then
    printf 'Missing cargo executable for --with-nusb\n' >&2
    [ "${DRY_RUN}" -eq 0 ] && exit 1
  fi
  run_cmd env -C "${APP_DIR}/native/dji_mic_usb" "${CARGO_BIN}" build --release
  run_cmd cp "${APP_DIR}/native/dji_mic_usb/target/release/libdji_mic_usb.so" "${BUNDLE_DIR}/lib/"
fi

if [ "${DRY_RUN}" -eq 0 ] && [ -x "${BUNDLE_DIR}/dji_mic_control" ]; then
  printf '\n--- Shared library audit (dji_mic_control) ---\n'
  ldd "${BUNDLE_DIR}/dji_mic_control"
  if [ -f "${BUNDLE_DIR}/lib/libdji_mic_usb.so" ]; then
    printf '\n--- Shared library audit (libdji_mic_usb.so) ---\n'
    ldd "${BUNDLE_DIR}/lib/libdji_mic_usb.so"
  fi
fi
