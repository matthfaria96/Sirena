/// ZoneLayout.swift
///
/// The layouts of the snap popup (drag a window to the top middle of a display, pick a zone):
/// HyprMac's splits as a tree. A node is either a zone or a split into columns or rows, each
/// child with its share. The tree keeps the zones covering the screen and every line between
/// two of them movable, which is how a window resized in a zone makes its neighbours follow.
///
/// Pure geometry in Accessibility coordinates (origin top left, y down), or any y-down space
/// (the popup's thumbnails). No AX here.

import CoreGraphics

struct ZoneNode: Hashable {
    enum Axis { case columns, rows }

    /// nil for a zone.
    var axis: Axis?
    /// Each child's share of this node, summing to 1.
    var sizes: [Double]
    var children: [ZoneNode]

    static let zone = ZoneNode(axis: nil, sizes: [], children: [])

    static func split(_ axis: Axis, _ children: [ZoneNode], sizes: [Double]? = nil) -> ZoneNode {
        let even = Array(repeating: 1 / Double(max(1, children.count)), count: children.count)
        return ZoneNode(axis: axis, sizes: sizes ?? even, children: children)
    }

}

/// A line between two children of a split, which can be dragged.
struct ZoneDivider: Equatable {
    /// Child indices from the root to the split.
    let path: [Int]
    /// Between child `index` and `index + 1`.
    let index: Int
    let axis: ZoneNode.Axis
    /// The line itself (zero thickness), in the space it was computed in.
    let line: CGRect

    /// Its position across the axis (x for columns, y for rows).
    var position: CGFloat { axis == .columns ? line.minX : line.minY }
}

/// The stretch of a line between windows of a group: from `low` to `high` along it.
struct ZoneSeam: Equatable {
    let divider: ZoneDivider
    let low: CGFloat
    let high: CGFloat

    var from: CGPoint { divider.axis == .columns ? CGPoint(x: divider.position, y: low) : CGPoint(x: low, y: divider.position) }
    var to: CGPoint { divider.axis == .columns ? CGPoint(x: divider.position, y: high) : CGPoint(x: high, y: divider.position) }
    var center: CGPoint { CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2) }
}

enum ZoneGeometry {
    /// The smallest share a child can be dragged down to.
    static let minShare = 0.06

    // MARK: - Frames

    /// The zones' regions, depth first, without gaps.
    static func regions(_ root: ZoneNode, in rect: CGRect) -> [CGRect] {
        guard let axis = root.axis, !root.children.isEmpty else { return [rect] }
        return zip(root.children, childRects(root, axis: axis, in: rect)).flatMap { regions($0, in: $1) }
    }

    /// The frames windows get: half a gap around the area and around each zone, so there is a
    /// full gap between two windows and at the screen edges, like Rectangle's actions.
    static func frames(_ root: ZoneNode, in area: CGRect, gap: CGFloat) -> [CGRect] {
        let half = max(0, gap) / 2
        return regions(root, in: area.insetBy(dx: half, dy: half)).map { rounded($0.insetBy(dx: half, dy: half)) }
    }

    /// Every draggable line, for the area as `frames` lays it out (inset by half a gap).
    static func dividers(_ root: ZoneNode, in rect: CGRect, path: [Int] = []) -> [ZoneDivider] {
        guard let axis = root.axis, !root.children.isEmpty else { return [] }
        let rects = childRects(root, axis: axis, in: rect)
        var result: [ZoneDivider] = []
        for index in 0..<(rects.count - 1) {
            let edge = rects[index]
            let line = axis == .columns
                ? CGRect(x: edge.maxX, y: rect.minY, width: 0, height: rect.height)
                : CGRect(x: rect.minX, y: edge.maxY, width: rect.width, height: 0)
            result.append(ZoneDivider(path: path, index: index, axis: axis, line: line))
        }
        for (index, child) in root.children.enumerated() {
            result += dividers(child, in: rects[index], path: path + [index])
        }
        return result
    }

    // MARK: - Dragging a line

    /// The layout with `divider` moved to `position` (same space as the divider was found in).
    static func moving(_ divider: ZoneDivider, to position: CGFloat, root: ZoneNode, in rect: CGRect) -> ZoneNode {
        var root = root
        // The split's own rect.
        var nodeRect = rect
        var node = root
        for index in divider.path {
            guard let axis = node.axis, index < node.children.count else { return root }
            nodeRect = childRects(node, axis: axis, in: nodeRect)[index]
            node = node.children[index]
        }
        guard let axis = node.axis, divider.index + 1 < node.sizes.count else { return root }
        let start = axis == .columns ? nodeRect.minX : nodeRect.minY
        let length = axis == .columns ? nodeRect.width : nodeRect.height
        guard length > 1 else { return root }
        let before = node.sizes[..<divider.index].reduce(0, +)
        let pair = node.sizes[divider.index] + node.sizes[divider.index + 1]
        let wanted = (Double(position - start) / Double(length)) - before
        let first = min(max(wanted, minShare), pair - minShare)
        node.sizes[divider.index] = first
        node.sizes[divider.index + 1] = pair - first
        root.replace(at: divider.path, with: node)
        return root
    }

    /// The two sides of `divider` made equal again (a double click on its grip).
    static func evening(_ divider: ZoneDivider, root: ZoneNode) -> ZoneNode {
        var root = root
        var node = root.node(at: divider.path)
        guard divider.index + 1 < node.sizes.count else { return root }
        let pair = node.sizes[divider.index] + node.sizes[divider.index + 1]
        node.sizes[divider.index] = pair / 2
        node.sizes[divider.index + 1] = pair / 2
        root.replace(at: divider.path, with: node)
        return root
    }

    /// The two sides of `divider` trade places ("Inverter lados"): the windows on the left go
    /// right, and so on. `moved[old]` is the zone each old zone's window goes to.
    static func swappingSides(_ divider: ZoneDivider, root: ZoneNode) -> (root: ZoneNode, moved: [Int]) {
        var node = root.node(at: divider.path)
        let i = divider.index
        guard i + 1 < node.children.count else { return (root, Array(leafPaths(root).indices)) }
        node.children.swapAt(i, i + 1)
        node.sizes.swapAt(i, i + 1)
        var swapped = root
        swapped.replace(at: divider.path, with: node)
        let oldPaths = leafPaths(root)
        let newPaths = leafPaths(swapped)
        let depth = divider.path.count
        let moved = oldPaths.enumerated().map { index, path -> Int in
            var path = path
            if path.count > depth, Array(path.prefix(depth)) == divider.path, path[depth] == i || path[depth] == i + 1 {
                path[depth] = path[depth] == i ? i + 1 : i
            }
            return newPaths.firstIndex(of: path) ?? index
        }
        return (swapped, moved)
    }

    /// The child indices leading to every zone, depth first (the zones' order).
    static func leafPaths(_ root: ZoneNode, path: [Int] = []) -> [[Int]] {
        guard !root.children.isEmpty else { return [path] }
        return root.children.enumerated().flatMap { leafPaths($1, path: path + [$0]) }
    }

    /// A window in a zone was resized by hand from `old` to `new` (frames with gaps): the
    /// lines its moved edges sat on follow them, so its neighbours make room.
    static func resizing(from old: CGRect, to new: CGRect, root: ZoneNode,
                         in area: CGRect, gap: CGFloat) -> ZoneNode {
        let half = max(0, gap) / 2
        let rect = area.insetBy(dx: half, dy: half)
        var root = root
        // (old line, new line, axis, the zone's extent along the line)
        let edges: [(CGFloat, CGFloat, ZoneNode.Axis, ClosedRange<CGFloat>)] = [
            (old.minX - half, new.minX - half, .columns, old.minY...old.maxY),
            (old.maxX + half, new.maxX + half, .columns, old.minY...old.maxY),
            (old.minY - half, new.minY - half, .rows, old.minX...old.maxX),
            (old.maxY + half, new.maxY + half, .rows, old.minX...old.maxX)
        ]
        for (from, to, axis, extent) in edges where abs(from - to) > 6 {
            let candidates = dividers(root, in: rect).filter { divider in
                guard divider.axis == axis, abs(divider.position - from) <= 4 else { return false }
                let span = axis == .columns ? divider.line.minY...divider.line.maxY : divider.line.minX...divider.line.maxX
                return span.overlaps(extent)
            }
            // The innermost line is the one this zone actually touches.
            if let divider = candidates.max(by: { $0.path.count < $1.path.count }) {
                root = moving(divider, to: to, root: root, in: rect)
            }
        }
        return root
    }

    // MARK: - Seams

    /// The part of each line that windows on both of its sides share, given the zones that
    /// hold a window (`occupied`): where a group shows it is held together, and where its grip
    /// goes. A line with a window on one side only has none.
    static func seams(_ root: ZoneNode, in rect: CGRect, occupied: Set<Int>) -> [ZoneSeam] {
        let regions = regions(root, in: rect)
        return dividers(root, in: rect).compactMap { divider in
            let columns = divider.axis == .columns
            let line = divider.line
            func extent(before: Bool) -> ClosedRange<CGFloat>? {
                let touching = regions.indices.filter { index in
                    guard occupied.contains(index) else { return false }
                    let region = regions[index]
                    if columns {
                        return abs((before ? region.maxX : region.minX) - line.minX) <= 1 && region.minY < line.maxY && region.maxY > line.minY
                    }
                    return abs((before ? region.maxY : region.minY) - line.minY) <= 1 && region.minX < line.maxX && region.maxX > line.minX
                }.map { regions[$0] }
                guard let low = touching.map({ columns ? $0.minY : $0.minX }).min(),
                      let high = touching.map({ columns ? $0.maxY : $0.maxX }).max() else { return nil }
                return low...high
            }
            guard let before = extent(before: true), let after = extent(before: false) else { return nil }
            let low = max(before.lowerBound, after.lowerBound, columns ? line.minY : line.minX)
            let high = min(before.upperBound, after.upperBound, columns ? line.maxY : line.maxX)
            guard high > low else { return nil }
            return ZoneSeam(divider: divider, low: low, high: high)
        }
    }

    // MARK: - Windows that can't get smaller

    /// Where `divider` may go when it is asked to go to `position`, so that no zone gets
    /// smaller than the size its window is known to keep (`minimums`, by zone, as frames with
    /// gaps): the line stops there instead of sliding a window under its neighbour. Only the
    /// zones on its two sides count; when both sides are at their minimum it stays between.
    static func clamping(_ divider: ZoneDivider, to position: CGFloat, root: ZoneNode,
                         in area: CGRect, gap: CGFloat, minimums: [Int: CGSize]) -> CGFloat {
        guard !minimums.isEmpty else { return position }
        let half = max(0, gap) / 2
        let rect = area.insetBy(dx: half, dy: half)
        let paths = leafPaths(root)
        let before = divider.path + [divider.index]
        let after = divider.path + [divider.index + 1]
        var low = -CGFloat.infinity
        var high = CGFloat.infinity
        var position = position
        for _ in 0..<8 {
            let frames = frames(moving(divider, to: position, root: root, in: rect), in: area, gap: gap)
            var settled = true
            for (zone, minimum) in minimums where zone < frames.count && zone < paths.count {
                let missing = divider.axis == .columns ? minimum.width - frames[zone].width : minimum.height - frames[zone].height
                guard missing > 0.5 else { continue }
                if paths[zone].starts(with: before) {
                    low = max(low, position + missing)
                    settled = false
                } else if paths[zone].starts(with: after) {
                    high = min(high, position - missing)
                    settled = false
                }
            }
            if settled { return position }
            if low > high { return ((low + high) / 2).rounded() }
            position = min(max(position, low), high)
        }
        return position
    }

    /// `root` with its lines moved as little as it takes for every zone to be as big as its
    /// window is known to stay (`minimums`, by zone, as frames with gaps): a window that
    /// won't shrink into its zone gets the room, and its neighbours give it.
    static func makingRoom(for minimums: [Int: CGSize], root: ZoneNode, in area: CGRect, gap: CGFloat) -> ZoneNode {
        guard !minimums.isEmpty else { return root }
        let half = max(0, gap) / 2
        let rect = area.insetBy(dx: half, dy: half)
        var root = root
        // Twice: a line moved for one zone can take room from another.
        for _ in 0..<2 {
            var moved = false
            for index in dividers(root, in: rect).indices {
                // Found again each time: moving a line shifts the ones inside its sides.
                let divider = dividers(root, in: rect)[index]
                let held = clamping(divider, to: divider.position, root: root, in: area, gap: gap, minimums: minimums)
                if abs(held - divider.position) > 0.5 {
                    root = moving(divider, to: held, root: root, in: rect)
                    moved = true
                }
            }
            if !moved { break }
        }
        return root
    }

    // MARK: - Displays

    /// The display (index in `displays`) most of `frame` is on, nil when it is on none.
    static func display(of frame: CGRect, in displays: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, display) in displays.enumerated() {
            let shared = display.intersection(frame)
            guard !shared.isNull, shared.width > 0, shared.height > 0 else { continue }
            let area = shared.width * shared.height
            if area > (best?.area ?? 0) { best = (index, area) }
        }
        return best?.index
    }

    // MARK: - Helpers

    private static func childRects(_ node: ZoneNode, axis: ZoneNode.Axis, in rect: CGRect) -> [CGRect] {
        let total = max(node.sizes.reduce(0, +), 0.0001)
        var offset: CGFloat = 0
        let length = axis == .columns ? rect.width : rect.height
        return node.sizes.enumerated().map { index, size in
            let isLast = index == node.sizes.count - 1
            let part = isLast ? length - offset : (length * CGFloat(size / total)).rounded()
            defer { offset += part }
            return axis == .columns
                ? CGRect(x: rect.minX + offset, y: rect.minY, width: part, height: rect.height)
                : CGRect(x: rect.minX, y: rect.minY + offset, width: rect.width, height: part)
        }
    }

    private static func rounded(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(),
               width: max(1, rect.width.rounded()), height: max(1, rect.height.rounded()))
    }
}

extension ZoneNode {
    func node(at path: [Int]) -> ZoneNode {
        path.reduce(self) { node, index in index < node.children.count ? node.children[index] : node }
    }

    mutating func replace(at path: [Int], with node: ZoneNode) {
        guard let first = path.first else {
            self = node
            return
        }
        guard first < children.count else { return }
        children[first].replace(at: Array(path.dropFirst()), with: node)
    }
}

// MARK: - Snap Assist's picker

/// How Snap Assist lays the window cards in a zone `width` points wide, and how the arrow keys
/// move through them. Shared by the view and the keyboard, so the two can't disagree.
struct ZonePickerLayout: Equatable {
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 12

    let columns: Int
    let cardWidth: CGFloat

    init(width: CGFloat) {
        let inner = max(0, width - Self.padding * 2)
        // Narrow zones get smaller cards, so a few still fit side by side.
        let minimum = min(200, max(130, width / 3.4))
        let columns = max(1, min(6, Int((inner + Self.spacing) / (minimum + Self.spacing))))
        self.columns = columns
        cardWidth = min(280, max(60, ((inner - CGFloat(columns - 1) * Self.spacing) / CGFloat(columns)).rounded(.down)))
    }

    /// A stretch of one app's cards on a row: `group` is the app's index, `range` which of its
    /// cards. The app's header goes above the stretch that starts at its first card.
    struct Block: Hashable {
        let group: Int
        let range: Range<Int>
        var isFirst: Bool { range.lowerBound == 0 }
    }

    /// The apps' cards (`counts`: how many each has) packed in rows of `columns`: apps follow
    /// each other on a row while they fit whole, so a dozen apps with one window each take a
    /// few rows, not a dozen; an app with more cards than a row takes rows of its own.
    static func packing(_ counts: [Int], columns: Int) -> [[Block]] {
        let columns = max(1, columns)
        var rows: [[Block]] = []
        var current: [Block] = []
        var used = 0
        for (group, count) in counts.enumerated() where count > 0 {
            if count > columns {
                if !current.isEmpty { rows.append(current) }
                current = []
                used = 0
                for start in stride(from: 0, to: count, by: columns) {
                    rows.append([Block(group: group, range: start..<min(start + columns, count))])
                }
                continue
            }
            if used + count > columns {
                rows.append(current)
                current = []
                used = 0
            }
            current.append(Block(group: group, range: 0..<count))
            used += count
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    /// The cards row by row, as `packing` lays them (for the arrow keys).
    static func rows<ID>(_ groups: [[ID]], columns: Int) -> [[ID]] {
        packing(groups.map(\.count), columns: columns).map { row in
            row.flatMap { Array(groups[$0.group][$0.range]) }
        }
    }

    /// The card the keyboard goes to from `current`: ← → through all of them in order (around
    /// the ends), ↑ ↓ to the row above or below, in the same column when it has one.
    static func moving<ID: Equatable>(from current: ID?, dx: Int, dy: Int, in rows: [[ID]]) -> ID? {
        let flat = rows.flatMap { $0 }
        guard !flat.isEmpty else { return nil }
        guard let current, let row = rows.firstIndex(where: { $0.contains(current) }),
              let column = rows[row].firstIndex(of: current) else {
            return dx < 0 || dy < 0 ? flat.last : flat.first
        }
        if dy != 0 {
            let target = row + (dy > 0 ? 1 : -1)
            guard rows.indices.contains(target) else { return current }
            return rows[target][min(column, rows[target].count - 1)]
        }
        guard dx != 0, let index = flat.firstIndex(of: current) else { return current }
        return flat[(index + (dx > 0 ? 1 : -1) + flat.count) % flat.count]
    }
}

// MARK: - The layouts of the popup

enum ZoneTemplate: Int, CaseIterable, Identifiable {
    case twoColumns, mainAndSide, mainAndStack, threeColumns, threeRows, grid
    case sideAndMain, stackAndMain, mainAndThreeStack, fourColumns, sixths, centered, centerAndStacks
    case twoRows, topAndTwo

    var id: Int { rawValue }

    var root: ZoneNode {
        switch self {
        case .twoColumns: return .split(.columns, [.zone, .zone])
        case .mainAndSide: return .split(.columns, [.zone, .zone], sizes: [0.66, 0.34])
        case .sideAndMain: return .split(.columns, [.zone, .zone], sizes: [0.34, 0.66])
        case .mainAndStack: return .split(.columns, [.zone, .split(.rows, [.zone, .zone])])
        case .stackAndMain: return .split(.columns, [.split(.rows, [.zone, .zone]), .zone])
        case .mainAndThreeStack: return .split(.columns, [.zone, .split(.rows, [.zone, .zone, .zone])], sizes: [0.6, 0.4])
        case .threeColumns: return .split(.columns, [.zone, .zone, .zone])
        case .fourColumns: return .split(.columns, [.zone, .zone, .zone, .zone])
        case .threeRows: return .split(.rows, [.zone, .zone, .zone])
        case .twoRows: return .split(.rows, [.zone, .zone])
        case .topAndTwo: return .split(.rows, [.zone, .split(.columns, [.zone, .zone])], sizes: [0.55, 0.45])
        case .grid: return .split(.columns, [.split(.rows, [.zone, .zone]), .split(.rows, [.zone, .zone])])
        case .sixths: return .split(.columns, [.split(.rows, [.zone, .zone]), .split(.rows, [.zone, .zone]),
                                               .split(.rows, [.zone, .zone])])
        case .centered: return .split(.columns, [.zone, .zone, .zone], sizes: [0.22, 0.56, 0.22])
        case .centerAndStacks: return .split(.columns, [.split(.rows, [.zone, .zone]), .zone, .split(.rows, [.zone, .zone])],
                                             sizes: [0.25, 0.5, 0.25])
        }
    }

    /// The smallest a zone may be, in points: below that a window gets cramped.
    static let minimumZone = CGSize(width: 400, height: 260)

    /// The layouts for a display whose usable area is `size`, most useful first. The order
    /// follows its shape (portrait, near square, regular, ultrawide); layouts whose smallest
    /// zone would be cramped there are left out (a 13" laptop doesn't get four columns), and a
    /// small display gets fewer choices than a big one (never more than 8: the panel stays
    /// short enough to aim at with a window in hand).
    static func fitting(_ size: CGSize) -> [ZoneTemplate] {
        let aspect = size.height > 0 ? size.width / size.height : 1.6
        let preferred: [ZoneTemplate]
        switch aspect {
        case ..<1.0:
            preferred = [.twoRows, .threeRows, .topAndTwo, .grid, .twoColumns, .sixths]
        case ..<1.3:
            preferred = [.twoColumns, .twoRows, .grid, .mainAndStack, .topAndTwo, .mainAndSide, .threeRows]
        case ..<2.0:
            preferred = [.twoColumns, .mainAndSide, .threeColumns, .mainAndStack, .grid, .sideAndMain,
                         .stackAndMain, .mainAndThreeStack, .sixths, .centered, .twoRows, .threeRows]
        default:
            preferred = [.threeColumns, .centered, .twoColumns, .centerAndStacks, .fourColumns, .mainAndSide,
                         .mainAndStack, .sixths, .grid, .sideAndMain]
        }
        let area = CGRect(origin: .zero, size: size)
        let roomy = preferred.filter { template in
            ZoneGeometry.regions(template.root, in: area).allSatisfy {
                $0.width >= minimumZone.width - 0.5 && $0.height >= minimumZone.height - 0.5
            }
        }
        // However small, a display still gets its two halves.
        guard !roomy.isEmpty else { return [aspect < 1 ? .twoRows : .twoColumns] }
        let shown = size.width * size.height < 1800 * 1000 ? 6 : 8
        return Array(roomy.prefix(shown))
    }
}
