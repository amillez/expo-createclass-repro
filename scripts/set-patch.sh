#!/usr/bin/env bash
# Applies (on) or reverts (off) the shared class factory patches in patches/.
# Usage: scripts/set-patch.sh on|off
set -euo pipefail
cd "$(dirname "$0")/.."

is_applied() {
  grep -q __expo_class_factory__ node_modules/expo-modules-core/common/cpp/JSI/JSIUtils.cpp
}

case "${1:-}" in
  on) is_applied || npx patch-package ;;
  off) if is_applied; then npx patch-package --reverse; fi ;;
  *) echo "usage: $0 on|off" >&2; exit 1 ;;
esac
echo "createClass patch: $(is_applied && echo on || echo off)"
