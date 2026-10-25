#!/bin/sh
# Compiles and runs the tests for the event tap safety policy (AccessibilityGuard's
# decisions) without building or launching the app.
set -eu
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/sirena-event-tap-policy-tests"
xcrun swiftc -O -o "$OUT" DockKit/Utilities/EventTapPolicy.swift scripts/tests/event-tap-policy/main.swift
"$OUT"
