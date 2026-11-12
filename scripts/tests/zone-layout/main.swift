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

// The layouts.
do {
    let counts = ZoneTemplate.allCases.map { ZoneGeometry.regions($0.root, in: area).count }
    expect(counts == [2, 2, 3, 3, 3, 4, 2, 3, 4, 4, 6, 3, 5, 2, 3], "zones per layout: \(counts)")
    for template in ZoneTemplate.allCases {
        let regions = ZoneGeometry.regions(template.root, in: area)
        expect(near(regions.map { $0.width * $0.height }.reduce(0, +), area.width * area.height, 2),
               "\(template): the zones cover the area")
    }
    let side = ZoneGeometry.regions(ZoneTemplate.mainAndSide.root, in: CGRect(x: 0, y: 0, width: 93, height: 58))
    expect(near(side[0].width, 61), "main + side keeps two thirds for the main zone: \(side)")
}

// Each display gets the layouts that suit its size and shape.
do {
    func names(_ width: CGFloat, _ height: CGFloat) -> [ZoneTemplate] { ZoneTemplate.fitting(CGSize(width: width, height: height)) }
    let laptop = names(1470, 880)     // 13" MacBook Air
    let big = names(2560, 1390)       // 27" display
    let ultrawide = names(3440, 1390) // 34" ultrawide
    let portrait = names(1080, 1870)  // a 24" display turned
    let tiny = names(1024, 700)
    for (name, list, size) in [("laptop", laptop, CGSize(width: 1470, height: 880)), ("big", big, CGSize(width: 2560, height: 1390)),
                               ("ultrawide", ultrawide, CGSize(width: 3440, height: 1390)),
                               ("portrait", portrait, CGSize(width: 1080, height: 1870))] {
        let cramped = list.filter { template in
            ZoneGeometry.regions(template.root, in: CGRect(origin: .zero, size: size)).contains {
                $0.width < ZoneTemplate.minimumZone.width - 1 || $0.height < ZoneTemplate.minimumZone.height - 1
            }
        }
        expect(cramped.isEmpty, "\(name): no cramped layout: \(cramped)")
        expect(Set(list).count == list.count, "\(name): no layout twice")
    }
    expect(laptop.first == .twoColumns && laptop.count == 6 && !laptop.contains(.fourColumns),
           "laptop: halves first, six choices, no four columns: \(laptop)")
    expect(big.count == 8 && big.contains(.mainAndThreeStack), "27\": more choices: \(big)")
    expect(ultrawide.first == .threeColumns && ultrawide.contains(.fourColumns) && ultrawide.contains(.centered)
           && ultrawide.count == 8,
           "ultrawide: columns and a centred main zone: \(ultrawide)")
    expect(portrait.first == .twoRows && !portrait.contains(.threeColumns), "portrait: rows first, no thin columns: \(portrait)")
    expect(tiny.first == .twoColumns && !tiny.contains(.threeColumns) && !tiny.contains(.mainAndSide),
           "1024 × 700: no thirds, no narrow side zone: \(tiny)")
    expect(names(600, 400) == [.twoColumns] && names(400, 700) == [.twoRows], "a tiny display still gets its two halves")
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

// "Inverter lados": the two sides of a line trade places, windows follow.
do {
    let two = ZoneTemplate.twoColumns.root
    let swapped = ZoneGeometry.swappingSides(ZoneGeometry.dividers(two, in: area)[0], root: two)
    expect(swapped.moved == [1, 0], "two columns: left and right trade: \(swapped.moved)")

    let side = ZoneTemplate.mainAndSide.root
    let flipped = ZoneGeometry.swappingSides(ZoneGeometry.dividers(side, in: area)[0], root: side)
    let frames = ZoneGeometry.frames(flipped.root, in: area, gap: 0)
    expect(near(frames[0].width, 1600 * 0.34, 2) && near(frames[1].width, 1600 * 0.66, 2),
           "main + side: the main zone moves right with its size: \(frames)")

    let stack = ZoneTemplate.mainAndStack.root // A | (B / C)
    let column = ZoneGeometry.swappingSides(ZoneGeometry.dividers(stack, in: area)[0], root: stack)
    expect(column.moved == [2, 0, 1], "1 + 2, the column line: A goes right, B and C go left in order: \(column.moved)")
    let rows = ZoneGeometry.swappingSides(ZoneGeometry.dividers(stack, in: area)[1], root: stack)
    expect(rows.moved == [0, 2, 1], "1 + 2, the row line: B and C trade, A stays: \(rows.moved)")
    expect(ZoneGeometry.leafPaths(ZoneTemplate.grid.root) == [[0, 0], [0, 1], [1, 0], [1, 1]], "leaf paths, depth first")
}

print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
