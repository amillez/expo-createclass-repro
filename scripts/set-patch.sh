#!/usr/bin/env bash
# Applies (on) or reverts (off) the shared class factory patches in patches/.
# Usage: scripts/set-patch.sh on|off
set -euo pipefail
cd "$(dirname "$0")/.."

patched_files=(
  node_modules/expo-modules-core/common/cpp/JSI/JSIUtils.cpp
  node_modules/expo-modules-jsi/apple/Sources/ExpoModulesJSI/Runtime/JavaScriptRuntime.swift
)

state() { # on, off, or partial
  local count=0
  for file in "${patched_files[@]}"; do
    if grep -q __expo_class_factory__ "$file"; then count=$((count + 1)); fi
  done
  case $count in 0) echo off ;; "${#patched_files[@]}") echo on ;; *) echo partial ;; esac
}

target=${1:-}
case "$target" in on | off) ;; *) echo "usage: $0 on|off" >&2; exit 1 ;; esac

current=$(state)
if [ "$current" = partial ]; then
  echo "patches are partially applied; reinstall node_modules" >&2
  exit 1
fi
if [ "$current" != "$target" ]; then
  if [ "$target" = on ]; then npx patch-package --error-on-fail; else npx patch-package --reverse --error-on-fail; fi
fi
current=$(state)
[ "$current" = "$target" ] || { echo "createClass patch is $current, expected $target" >&2; exit 1; }
echo "createClass patch: $current"
