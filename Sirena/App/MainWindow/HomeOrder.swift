/// HomeOrder.swift
///
/// The order the user gave Home's cards by dragging them; the ⚡ menu follows it too.

import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class HomeOrder {
    static let shared = HomeOrder()
    private static let key = "home.order"
    private var orders: [String: [String]]

    private init() {
        orders = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: [String]] ?? [:]
    }

    /// `items` sorted by the saved order; new items keep their place at the end.
    func sorted<T>(_ items: [T], group: String, id: (T) -> String) -> [T] {
        guard let saved = orders[group] else { return items }
        let rank = Dictionary(saved.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return items.enumerated()
            .sorted { (rank[id($0.element)] ?? saved.count + $0.offset) < (rank[id($1.element)] ?? saved.count + $1.offset) }
            .map(\.element)
    }

    /// Puts `moved` where `target` is, within the group's current order.
    func move(_ moved: String, to target: String, in current: [String], group: String) {
        guard moved != target, var order = Optional(current), let from = order.firstIndex(of: moved),
              let to = order.firstIndex(of: target) else { return }
        order.remove(at: from)
        order.insert(moved, at: to)
        orders[group] = order
        UserDefaults.standard.set(orders, forKey: Self.key)
    }

    func reset(_ group: String) {
        orders[group] = nil
        UserDefaults.standard.set(orders, forKey: Self.key)
    }

    func isCustom(_ group: String) -> Bool { orders[group] != nil }
}

/// Makes a Home card draggable onto its siblings, with a grip that shows on hover.
struct Reorderable: ViewModifier {
    let id: String
    let group: String
    let ids: [String]
    @State private var isTargeted = false
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(8)
                    .opacity(isHovering ? 1 : 0)
                    .help(L("Drag to move"))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .opacity(isTargeted ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .onHover { hovering in withAnimation(.snappy(duration: 0.15)) { isHovering = hovering } }
            .draggable(id) {
                Label(L("Move"), systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    .padding(8)
                    .glassEffect(.regular, in: Capsule())
            }
            .dropDestination(for: String.self) { items, _ in
                guard let moved = items.first, ids.contains(moved) else { return false }
                withAnimation(.snappy) { HomeOrder.shared.move(moved, to: id, in: ids, group: group) }
                return true
            } isTargeted: { targeted in
                withAnimation(.snappy(duration: 0.15)) { isTargeted = targeted }
            }
    }
}
