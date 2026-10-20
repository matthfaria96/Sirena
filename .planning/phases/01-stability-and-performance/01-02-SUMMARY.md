---
phase: 01-stability-and-performance
plan: 02
subsystem: window-gestures
tags: [event-tap, accessibility]
requires: ["01-01"]
key-files:
  modified:
    - DockKit/Utilities/Window Gestures/WindowGestureController.swift
requirements-completed: [STAB-03]
completed: 2026-10-20
---

# Phase 1 Plan 02: Gesture window-frame read off the tap thread Summary

The session-start AX frame read (`currentWindowFrame()`) now runs on a background queue (`captureWindowFrame`) and is posted back via `thread.perform`, only if the session's window id still matches. `Session.windowFrame` is now `var`, nil until the frame arrives (HUD region preview appears after it).

## Tasks
1. Move frame read off tap thread - commit see git log ("fix(01-02)"). Debug build: BUILD SUCCEEDED. WindowGestureExecutor.swift unchanged (already uses queue.async).
2. Owner check (gestures, input lag, no tapDisabledByTimeout): **pending owner verification**. Steps: quit installed Sirena, open ~/Library/Caches/sirena-dd/Build/Products/Debug/Sirena.app, snap a window with two-finger scroll on the title bar and confirm the HUD preview, type/scroll for ~30 s, check Console for tap-disabled lines.

## Deviations from Plan
None.

## Self-Check: PASSED
