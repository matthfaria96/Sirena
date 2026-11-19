#!/bin/sh
# Compiles and runs the tests for where a window goes when its app is set to open on another
# display (AppScreenPlacement.swift), without building or launching the app.
set -eu
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/sirena-app-screen-placement-tests"
xcrun swiftc -O -o "$OUT" Sirena/Modules/Adjustments/AppScreenPlacement.swift scripts/tests/app-screen-placement/main.swift
"$OUT"
