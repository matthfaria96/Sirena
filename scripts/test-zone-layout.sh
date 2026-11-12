#!/bin/sh
# Compiles and runs the tests for the snap layouts' geometry (ZoneLayout.swift) without
# building or launching the app.
set -eu
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/sirena-zone-layout-tests"
xcrun swiftc -O -o "$OUT" Sirena/Modules/WindowManagement/Zones/ZoneLayout.swift scripts/tests/zone-layout/main.swift
"$OUT"
