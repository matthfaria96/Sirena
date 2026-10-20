---
phase: 01-stability-and-performance
plan: 03
requirements-completed: [PERF-01, PERF-02]
key-files:
  modified:
    - DockKit/Models/MediaInfo.swift
    - DockKit/Views/Hover Window/Special Hover Windows/Media/MediaControlsView.swift
---
# Phase 1 Plan 03: Media polling and lyrics timer Summary

MediaInfo now polls osascript every 2 s (playing) or 5 s (paused) with timer tolerance, and the 20 Hz lyrics timer runs only while lyrics are visible, loaded, playing and the widget is open.

## Tasks
1. PERF-01 polling intervals: commit 0673ad0
2. PERF-02 gated lyrics timer (updateLyricsTimer, setLyricsVisible, onChange/onAppear wiring): see git log (second perf(01-03) commit)

## Verification
All grep acceptance gates pass; Debug build succeeded in ~/Library/Caches/sirena-dd. The runtime osascript count was not run (host Sirena must not be replaced).

## Pending owner verification
Task 3 (checkpoint:human-verify): poll rate with widget open, idle CPU with lyrics paused/hidden. Derived data ~/Library/Caches/sirena-dd intentionally NOT deleted; orchestrator deletes it at milestone end.

## Deviations
None.
