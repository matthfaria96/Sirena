// Focused tests for Sirena/Modules/WindowManagement/Zones/ZoneLayout.swift (the geometry of the
// snap layouts: frames with gaps, lines, moving a line, a window resized in a zone, evening).
// No app, no AX: compiled together with that file by scripts/test-zone-layout.sh.

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

func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1) -> Bool { abs(a - b) <= tolerance }

// A 1600 × 1000 usable area below a 25 pt menu bar.
let area = CGRect(x: 0, y: 25, width: 1600, height: 1000)

// Frames: a full gap at the screen edges and between windows.
do {
    let frames = ZoneGeometry.frames(ZoneTemplate.twoColumns.root, in: area, gap: 10)
    expect(frames == [CGRect(x: 10, y: 35, width: 785, height: 980), CGRect(x: 805, y: 35, width: 785, height: 980)],
           "two columns with a 10 pt gap: \(frames)")
    let stack = ZoneGeometry.frames(ZoneTemplate.mainAndStack.root, in: area, gap: 10)
    expect(stack.count == 3 && stack[1].minX == stack[2].minX, "1 + 2: the two on the right share a column: \(stack)")
    expect(near(stack[2].minY - stack[1].maxY, 10), "1 + 2: a gap between the two rows")
    let flush = ZoneGeometry.frames(ZoneTemplate.threeColumns.root, in: area, gap: 0)
    expect(flush.map(\.width).reduce(0, +) == area.width, "no gap: the zones cover the area exactly")
}

// The panel's six layouts.
do {
    let counts = ZoneTemplate.allCases.map { ZoneGeometry.regions($0.root, in: area).count }
    expect(counts == [2, 2, 3, 3, 3, 4], "zones per layout: \(counts)")
    let side = ZoneGeometry.regions(ZoneTemplate.mainAndSide.root, in: CGRect(x: 0, y: 0, width: 93, height: 58))
    expect(near(side[0].width, 61), "main + side keeps two thirds for the main zone: \(side)")
}

// Lines: one per pair of neighbours, and moving one leaves the others alone.
do {
    expect(ZoneGeometry.dividers(ZoneTemplate.threeColumns.root, in: area).count == 2, "three columns: two lines")
    expect(ZoneGeometry.dividers(ZoneTemplate.grid.root, in: area).count == 3, "four quarters: three lines")
    let root = ZoneTemplate.threeColumns.root
    let moved = ZoneGeometry.moving(ZoneGeometry.dividers(root, in: area)[1], to: 1300, root: root, in: area)
    let frames = ZoneGeometry.frames(moved, in: area, gap: 0)
    expect(near(frames[1].maxX, 1300) && near(frames[0].width, 533), "second line moved, first column kept: \(frames)")
    let squeezed = ZoneGeometry.moving(ZoneGeometry.dividers(root, in: area)[0], to: -500, root: root, in: area)
    expect(ZoneGeometry.frames(squeezed, in: area, gap: 0).allSatisfy { $0.width >= 1600 * ZoneGeometry.minShare - 1 },
           "a line can't squeeze a zone below the minimum share")
}

// A window resized by hand in a zone moves the lines it touches.
do {
    let root = ZoneTemplate.twoColumns.root
    let old = ZoneGeometry.frames(root, in: area, gap: 10)[0]
    var wider = old
    wider.size.width = 1000
    let frames = ZoneGeometry.frames(ZoneGeometry.resizing(from: old, to: wider, root: root, in: area, gap: 10), in: area, gap: 10)
    expect(near(frames[0].width, 1000) && near(frames[1].minX, 1020), "wider left window pushes the line: \(frames)")

    let stack = ZoneTemplate.mainAndStack.root
    let bottom = ZoneGeometry.frames(stack, in: area, gap: 10)[2]
    var taller = bottom
    taller.origin.y -= 200
    taller.size.height += 200
    let after = ZoneGeometry.frames(ZoneGeometry.resizing(from: bottom, to: taller, root: stack, in: area, gap: 10), in: area, gap: 10)
    expect(near(after[2].minY, taller.minY) && near(after[1].maxY + 10, after[2].minY), "the row line follows the top edge: \(after)")
    expect(after[0].width == old.width, "the column line is untouched")
}

// A double click on a grip gives both sides the same room.
do {
    let root = ZoneTemplate.mainAndSide.root
    let evened = ZoneGeometry.evening(ZoneGeometry.dividers(root, in: area)[0], root: root)
    let frames = ZoneGeometry.frames(evened, in: area, gap: 0)
    expect(near(frames[0].width, frames[1].width), "evened: \(frames)")
}

print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
