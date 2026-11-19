// Focused tests for Sirena/Modules/Adjustments/AppScreenPlacement.swift (where a window goes
// when its app is set to open on another display). No app, no AX: compiled together with that
// file by scripts/test-app-screen-placement.sh.

import CoreGraphics
import Foundation

var failures = 0
var checks = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    checks += 1
    if !condition() {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

// Two displays side by side (top-left coordinates): a 1440 × 900 laptop and a 2560 × 1440
// monitor to its right, top edges aligned. Usable areas leave 25 pt for the menu bar.
let laptop = CGRect(x: 0, y: 0, width: 1440, height: 900)
let monitor = CGRect(x: 1440, y: 0, width: 2560, height: 1440)
let laptopArea = CGRect(x: 0, y: 25, width: 1440, height: 875)
let monitorArea = CGRect(x: 1440, y: 25, width: 2560, height: 1415)

// Which display holds a window.
do {
    expect(AppScreenPlacement.screenIndex(of: CGRect(x: 100, y: 100, width: 800, height: 600), in: [laptop, monitor]) == 0,
           "a window on the laptop")
    expect(AppScreenPlacement.screenIndex(of: CGRect(x: 1300, y: 100, width: 800, height: 600), in: [laptop, monitor]) == 1,
           "a window mostly on the monitor goes with it")
    expect(AppScreenPlacement.screenIndex(of: CGRect(x: 5000, y: 5000, width: 100, height: 100), in: [laptop, monitor]) == nil,
           "a window off every display")
}

// Fill: the whole usable area.
do {
    let frame = AppScreenPlacement.frame(for: CGRect(x: 100, y: 100, width: 800, height: 600),
                                         from: laptopArea, to: monitorArea, mode: .fill)
    expect(frame == monitorArea, "fill takes the monitor's usable area: \(frame)")
}

// Centre: same size, centred.
do {
    let frame = AppScreenPlacement.frame(for: CGRect(x: 100, y: 100, width: 800, height: 600),
                                         from: laptopArea, to: monitorArea, mode: .center)
    expect(frame.size == CGSize(width: 800, height: 600), "centre keeps the size: \(frame)")
    expect(abs(frame.midX - monitorArea.midX) <= 1 && abs(frame.midY - monitorArea.midY) <= 1, "centre centres: \(frame)")
}

// Keep: same size and the same relative spot.
do {
    // Top-left corner of the laptop → top-left corner of the monitor.
    let topLeft = AppScreenPlacement.frame(for: CGRect(x: 0, y: 25, width: 800, height: 600),
                                           from: laptopArea, to: monitorArea, mode: .keep)
    expect(topLeft == CGRect(x: 1440, y: 25, width: 800, height: 600), "top-left stays top-left: \(topLeft)")
    // Bottom-right → bottom-right.
    let bottomRight = AppScreenPlacement.frame(for: CGRect(x: 640, y: 300, width: 800, height: 600),
                                               from: laptopArea, to: monitorArea, mode: .keep)
    expect(bottomRight.maxX == monitorArea.maxX && bottomRight.maxY == monitorArea.maxY,
           "bottom-right stays bottom-right: \(bottomRight)")
    // Centred → centred.
    let centred = AppScreenPlacement.frame(for: CGRect(x: 320, y: 162, width: 800, height: 600),
                                           from: laptopArea, to: monitorArea, mode: .keep)
    expect(abs(centred.midX - monitorArea.midX) <= 2 && abs(centred.midY - monitorArea.midY) <= 2,
           "centred stays centred: \(centred)")
}

// A window bigger than the target shrinks to fit and stays inside.
do {
    let big = CGRect(x: 1440, y: 25, width: 2560, height: 1415)
    for mode in [AppScreenPlacementMode.keep, .center] {
        let frame = AppScreenPlacement.frame(for: big, from: monitorArea, to: laptopArea, mode: mode)
        expect(laptopArea.contains(frame), "\(mode) keeps a big window inside the laptop: \(frame)")
        expect(frame.size == laptopArea.size, "\(mode) shrinks a big window to the laptop's area: \(frame)")
    }
}

// A window that already fills its display (no room to move) lands in the middle with keep.
do {
    let frame = AppScreenPlacement.frame(for: laptopArea, from: laptopArea, to: monitorArea, mode: .keep)
    expect(monitorArea.contains(frame), "a filled window lands inside: \(frame)")
}

print(failures == 0 ? "OK: \(checks) checks" : "\(failures) of \(checks) checks failed")
exit(failures == 0 ? 0 : 1)
