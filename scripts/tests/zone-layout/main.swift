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

// A line stops where a window can't get smaller.
do {
    let root = ZoneTemplate.twoColumns.root
    let rect = area.insetBy(dx: 5, dy: 5)
    let line = ZoneGeometry.dividers(root, in: rect)[0]
    let free = ZoneGeometry.clamping(line, to: 300, root: root, in: area, gap: 10, minimums: [:])
    expect(free == 300, "no known minimum: the line goes where it is asked")
    // The left window keeps 500 pt: the line stops at its right edge (10 + 500 + half a gap).
    let held = ZoneGeometry.clamping(line, to: 300, root: root, in: area, gap: 10, minimums: [0: CGSize(width: 500, height: 100)])
    let frames = ZoneGeometry.frames(ZoneGeometry.moving(line, to: held, root: root, in: rect), in: area, gap: 10)
    expect(near(frames[0].width, 500, 1.5) && frames[1].minX >= frames[0].maxX + 9, "the left window keeps its 500 pt: \(frames)")
    let right = ZoneGeometry.clamping(line, to: 1500, root: root, in: area, gap: 10, minimums: [1: CGSize(width: 400, height: 100)])
    let pushed = ZoneGeometry.frames(ZoneGeometry.moving(line, to: right, root: root, in: rect), in: area, gap: 10)
    expect(near(pushed[1].width, 400, 1.5), "the right window keeps its 400 pt: \(pushed)")
    let fine = ZoneGeometry.clamping(line, to: 900, root: root, in: area, gap: 10, minimums: [0: CGSize(width: 500, height: 100), 1: CGSize(width: 400, height: 100)])
    expect(fine == 900, "room for both: untouched")
    // 1 + 2: the row line only answers to the two stacked windows; the main one doesn't count.
    let stack = ZoneTemplate.mainAndStack.root
    let rowLine = ZoneGeometry.dividers(stack, in: rect)[1]
    let rows = ZoneGeometry.clamping(rowLine, to: 100, root: stack, in: area, gap: 10,
                                     minimums: [0: CGSize(width: 5000, height: 5000), 1: CGSize(width: 100, height: 300)])
    let stacked = ZoneGeometry.frames(ZoneGeometry.moving(rowLine, to: rows, root: stack, in: rect), in: area, gap: 10)
    expect(near(stacked[1].height, 300, 1.5), "the top stacked window keeps its 300 pt: \(stacked)")
    // Both at their minimum: the line stays between them instead of flying off.
    let stuck = ZoneGeometry.clamping(line, to: 300, root: root, in: area, gap: 10,
                                      minimums: [0: CGSize(width: 900, height: 100), 1: CGSize(width: 900, height: 100)])
    expect(stuck > 600 && stuck < 1000, "both sides too big: somewhere in the middle: \(stuck)")
}

// A window that won't shrink into its zone gets the room; its neighbours give it.
do {
    let three = ZoneTemplate.threeColumns.root
    let roomy = ZoneGeometry.makingRoom(for: [1: CGSize(width: 900, height: 300)], root: three, in: area, gap: 10)
    let frames = ZoneGeometry.frames(roomy, in: area, gap: 10)
    expect(frames[1].width >= 899, "the middle column grows to 900: \(frames)")
    expect(frames[0].maxX + 9 <= frames[1].minX && frames[1].maxX + 9 <= frames[2].minX, "and nothing overlaps: \(frames)")
    expect(frames.allSatisfy { $0.minX >= 10 && $0.maxX <= 1590 }, "all inside the area")
    expect(ZoneGeometry.makingRoom(for: [1: CGSize(width: 300, height: 300)], root: three, in: area, gap: 10) == three,
           "a window that fits changes nothing")
    expect(ZoneGeometry.makingRoom(for: [:], root: three, in: area, gap: 10) == three, "nothing known, nothing moved")
    // 1 + 2: the bottom right window is too tall and too wide.
    let stack = ZoneTemplate.mainAndStack.root
    let fitted = ZoneGeometry.frames(ZoneGeometry.makingRoom(for: [2: CGSize(width: 1000, height: 700)], root: stack, in: area, gap: 10),
                                     in: area, gap: 10)
    expect(fitted[2].width >= 999 && fitted[2].height >= 699, "both of its lines move: \(fitted)")
    expect(near(fitted[1].maxY + 10, fitted[2].minY) && near(fitted[0].maxX + 10, fitted[2].minX), "its neighbours follow")
}

// One seam per line windows on both sides share, over the part they share.
do {
    let rect = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    let two = ZoneGeometry.seams(ZoneTemplate.twoColumns.root, in: rect, occupied: [0, 1])
    expect(two.count == 1 && two[0].from == CGPoint(x: 800, y: 0) && two[0].to == CGPoint(x: 800, y: 1000),
           "two columns: the whole line: \(two)")
    expect(ZoneGeometry.seams(ZoneTemplate.twoColumns.root, in: rect, occupied: [0]).isEmpty, "a window alone has no seam")
    let stack = ZoneTemplate.mainAndStack.root // A | (B / C)
    let all = ZoneGeometry.seams(stack, in: rect, occupied: [0, 1, 2])
    expect(all.count == 2 && all[0].high - all[0].low == 1000 && all[1].from.x == 800 && all[1].to.x == 1600,
           "1 + 2: the column line whole, the row line across the right half: \(all)")
    let topOnly = ZoneGeometry.seams(stack, in: rect, occupied: [0, 1])
    expect(topOnly.count == 1 && topOnly[0].low == 0 && topOnly[0].high == 500 && topOnly[0].center == CGPoint(x: 800, y: 250),
           "1 + the top one only: the seam stops where the top window does: \(topOnly)")
    let apart = ZoneGeometry.seams(ZoneTemplate.threeColumns.root, in: rect, occupied: [0, 2])
    expect(apart.isEmpty, "three columns, the outer two: no shared line")
}

// The display a window is on: the one holding most of it.
do {
    let displays = [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: -1080, y: -175, width: 1080, height: 1920),
                    CGRect(x: 2560, y: 237, width: 756, height: 1344)]
    expect(ZoneGeometry.display(of: CGRect(x: 1536, y: 30, width: 1024, height: 582), in: displays) == 0, "on the main display")
    expect(ZoneGeometry.display(of: CGRect(x: -1061, y: -135, width: 1080, height: 630), in: displays) == 1, "mostly on the left display")
    expect(ZoneGeometry.display(of: CGRect(x: 2400, y: 300, width: 600, height: 400), in: displays) == 2, "straddling: the bigger part wins")
    expect(ZoneGeometry.display(of: CGRect(x: 9000, y: 9000, width: 600, height: 400), in: displays) == nil, "off every display")
}

// Snap Assist's picker: the grid and the arrow keys.
do {
    let wide = ZonePickerLayout(width: 1270)
    expect(wide.columns == 5 && wide.cardWidth >= 200 && wide.cardWidth <= 280, "a half of a 27\" display: \(wide)")
    let narrow = ZonePickerLayout(width: 400)
    expect(narrow.columns == 2 && narrow.cardWidth >= 130, "the smallest zone still shows two side by side: \(narrow)")
    expect(ZonePickerLayout(width: 150).columns == 1, "never zero columns")
    let rows = ZonePickerLayout.rows([[1, 2, 3, 4, 5], [6], [7, 8]], columns: 3)
    expect(rows == [[1, 2, 3], [4, 5], [6, 7, 8]], "a big app takes its own rows, small ones share one: \(rows)")
    let packed = ZonePickerLayout.packing([1, 2, 1, 1, 1, 3], columns: 5)
    expect(packed.map { $0.map(\.group) } == [[0, 1, 2, 3], [4, 5]] && packed.allSatisfy { $0.allSatisfy(\.isFirst) },
           "apps share a row while they fit whole: \(packed)")
    expect(ZonePickerLayout.packing([0, 2], columns: 4).map { $0.map(\.group) } == [[1]], "an app without cards takes no room")
    let long = ZonePickerLayout.packing([7], columns: 3)
    expect(long.map { $0[0].range } == [0..<3, 3..<6, 6..<7] && long.map { $0[0].isFirst } == [true, false, false],
           "an app with many windows: its header once, on its first row: \(long)")
    func move(_ from: Int?, _ dx: Int, _ dy: Int) -> Int? { ZonePickerLayout.moving(from: from, dx: dx, dy: dy, in: rows) }
    expect(move(nil, 1, 0) == 1 && move(nil, -1, 0) == 8, "no card yet: the first, or the last going back")
    expect(move(3, 1, 0) == 4 && move(8, 1, 0) == 1 && move(1, -1, 0) == 8, "← →: in order, around the ends")
    expect(move(3, 0, 1) == 5 && move(5, 0, 1) == 7 && move(4, 0, 1) == 6, "↓: the row below, the nearest column")
    expect(move(2, 0, -1) == 2 && move(8, 0, 1) == 8, "↑ on the first row and ↓ on the last stay")
    expect(move(8, 0, -1) == 5 && move(4, 0, -1) == 1, "↑: the row above")
    expect(ZonePickerLayout.moving(from: 1, dx: 1, dy: 0, in: [[Int]]()) == nil, "nothing to move through")
}

print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
