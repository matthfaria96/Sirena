/// ShelfPanel.swift
///
/// The shelf on screen: a floating glass panel at the screen edge. Things dropped on it
/// are kept; items can be dragged back out, one by one or several at once (stacks).
/// Space opens Quick Look, Delete removes, ⌘C copies, ⌘A selects all.

import AppKit
import Quartz
import QuickLookThumbnailing
import SwiftUI

final class ShelfPanel: NSPanel {
    let shelfView = ShelfContentView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 110, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = shelfView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Drop target, keys and Quick Look

final class ShelfContentView: NSView {
    private let hosting = FirstMouseHostingView(rootView: ShelfView())
    private var isDropTargeted = false {
        didSet { ShelfController.shared.isDropTargeted = isDropTargeted }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff, .color, .rtf])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Dropping

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !(sender.draggingSource is ShelfCellView) else { return [] }
        isDropTargeted = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingSource is ShelfCellView ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTargeted = false
    }

    // A drag cancelled over the shelf never "exits": without this the highlight stays
    // and the empty shelf never hides.
    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTargeted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTargeted = false
        guard !(sender.draggingSource is ShelfCellView) else { return false }
        return ShelfStore.shared.add(from: sender.draggingPasteboard)
    }

    // Import from iPhone (Continuity Camera), offered in the shelf's menu

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?,
                                 returnType: NSPasteboard.PasteboardType?) -> Any? {
        if sendType == nil, let returnType, NSImage.imageTypes.contains(returnType.rawValue) { return self }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    // The shelf's menu (add from clipboard or iPhone, stacks, restore…) on right-click.
    override func rightMouseDown(with event: NSEvent) {
        ShelfController.shared.importsToShelf = true
        NSMenu.popUpContextMenu(ShelfActions.shelfMenu(), with: event, for: self)
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { ShelfController.shared.importsToShelf = false }
    }

    // Keys

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let store = ShelfStore.shared
        let command = event.modifierFlags.contains(.command)
        switch (event.keyCode, command, event.charactersIgnoringModifiers ?? "") {
        case (49, false, _): // Space
            toggleQuickLook()
        case (51, _, _), (117, _, _): // Delete, Forward Delete (locked items stay)
            store.remove(Set(store.items.filter { store.selection.contains($0.id) && !$0.isLocked }.map(\.id)))
        case (_, true, "a"):
            store.selection = Set(store.items.map(\.id))
        case (_, true, "c"):
            ShelfActions.copy(store.items.filter { store.selection.contains($0.id) })
        case (53, _, _): // Esc
            if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
                QLPreviewPanel.shared().orderOut(nil)
            } else {
                store.selection = []
            }
        default:
            super.keyDown(with: event)
        }
    }

    // Quick Look

    private var previewURLs: [URL] = []

    func toggleQuickLook() {
        let panel = QLPreviewPanel.shared()!
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            window?.makeFirstResponder(self)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        let store = ShelfStore.shared
        let selected = store.items.filter { store.selection.contains($0.id) }
        previewURLs = (selected.isEmpty ? store.items : selected).flatMap { item -> [URL] in
            if case .link(let url) = item.content { return [url] }
            return item.urls
        }
        panel.dataSource = self
        panel.reloadData()
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        previewURLs = []
    }
}

extension ShelfContentView: NSServicesMenuRequestor {
    func readSelection(from pasteboard: NSPasteboard) -> Bool {
        ShelfStore.shared.add(from: pasteboard)
    }
}

/// Lets the first click on a button work while the panel isn't key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension ShelfContentView: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURLs[index] as NSURL
    }
}

// MARK: - SwiftUI content

struct ShelfView: View {
    @State private var store = ShelfStore.shared
    @State private var controller = ShelfController.shared
    @State private var settings = ShelfSettings.shared

    var body: some View {
        GeometryReader { geometry in
            let full = CGSize(width: geometry.size.width - ShelfLayout.margin * 2,
                              height: geometry.size.height - ShelfLayout.margin * 2)
            let open = expansion
            // Peeking: a slim edge that widens (and grows taller) toward its full size.
            let width = controller.isPeeking ? 14 + (full.width - 14) * open : full.width
            let height = controller.isPeeking ? full.height * (0.55 + 0.45 * open) : full.height
            card(contentOpacity: controller.isPeeking ? max(0, (open - 0.3) / 0.7) : 1)
                .frame(width: max(width, 14), height: max(height, 40))
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: settings.position.isLeft ? .leading : .trailing)
                .padding(ShelfLayout.margin)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.74), value: expansion)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: controller.isPeeking)
    }

    /// 0 … 1: how far a peeking shelf has opened.
    private var expansion: Double {
        guard controller.isPeeking else { return 1 }
        if controller.isDropTargeted { return 1 }
        // Opens fast in the last stretch, like it reaches out to take the file.
        return min(1, pow(controller.dragProximity, 1.6) * 1.15)
    }

    private func card(contentOpacity: Double) -> some View {
        let side = settings.itemSize.side(for: store.items.count)
        // Docked to an edge: square on the screen side, rounded toward the screen.
        let radius: CGFloat = controller.isPeeking && expansion < 0.3 ? 7 : 20
        let docked = !settings.showAtCursor
        let left = settings.position.isLeft
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: docked && left ? 0 : radius,
            bottomLeadingRadius: docked && left ? 0 : radius,
            bottomTrailingRadius: docked && !left ? 0 : radius,
            topTrailingRadius: docked && !left ? 0 : radius,
            style: .continuous)
        let proximity = reduceMotion ? 0 : controller.dragProximity
        let targeted = controller.isDropTargeted
        let peekGlow = controller.isPeeking ? 0.35 + 0.4 * proximity : 0
        return VStack(spacing: 6) {
            header
            if store.items.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(store.items) { item in
                            ShelfCell(item: item, side: side)
                                .frame(width: side + 20, height: side + ShelfLayout.labelHeight)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.4).combined(with: .opacity),
                                    removal: .scale(scale: 0.7).combined(with: .opacity)))
                        }
                    }
                    .padding(.vertical, 4)
                    .animation(reduceMotion ? .default : .spring(response: 0.45, dampingFraction: 0.68), value: store.items.map(\.id))
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .opacity(contentOpacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Frosted glass: a real blur of what's behind, plus Liquid Glass for the rim and sheen.
        .background {
            ZStack {
                ShelfBlurView()
                LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                if controller.isPeeking {
                    Color.accentColor.opacity(0.18 * (1 - expansion) + (targeted ? 0.12 : 0))
                }
            }
            .clipShape(shape)
        }
        .glassEffect(.clear, in: shape)
        .overlay {
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                lineWidth: 0.8)
        }
        // Reacts to a drag: glows as it approaches, opens up when it's over.
        .overlay {
            shape.strokeBorder(Color.accentColor.opacity(targeted ? 0.95 : max(proximity * 0.6, peekGlow)), lineWidth: targeted ? 2.5 : 1.5)
                .shadow(color: .accentColor.opacity(targeted ? 0.7 : max(proximity * 0.45, peekGlow)), radius: targeted ? 14 : 9)
        }
        .scaleEffect(reduceMotion ? 1 : (controller.isPresented ? 1 + (controller.isPeeking ? 0 : 0.04 * proximity) + (targeted ? 0.04 : 0) : 0.88),
                     anchor: settings.position.isLeft ? .leading : .trailing)
        .opacity(controller.isPresented ? 1 : 0)
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.82), value: proximity)
        .animation(.spring(response: 0.34, dampingFraction: 0.6), value: targeted)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: controller.isPresented)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Two buttons, like Yoink: close the shelf, and clear everything on it. The rest
    /// of the shelf's commands are in its right-click menu.
    private var header: some View {
        HStack(spacing: 2) {
            headerButton(L("Remove All Files"), symbol: "trash") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { store.removeAll() }
            }
            .disabled(store.items.allSatisfy(\.isLocked))
            .opacity(store.items.allSatisfy(\.isLocked) ? 0.35 : 1)
            Spacer(minLength: 0)
            if !store.items.isEmpty {
                Text("\(store.items.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            headerButton(L("Hide Shelf"), symbol: "xmark") { controller.hide() }
        }
        .padding(.horizontal, 2)
        .frame(height: ShelfLayout.headerHeight)
    }

    private func headerButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.primary.opacity(0.85))
                .frame(width: 22, height: 22)
                .background(.white.opacity(0.14), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private var emptyState: some View {
        let targeted = controller.isDropTargeted
        let arrow = settings.position.isLeft ? "arrow.left" : "arrow.right"
        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(targeted ? 0.28 : 0.12))
                    .frame(width: 44, height: 44)
                    .scaleEffect(targeted ? 1.15 : 1)
                Image(systemName: targeted ? "tray.and.arrow.down.fill" : arrow)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolEffect(.bounce, value: targeted)
                    .symbolEffect(.wiggle, options: .repeating, isActive: controller.isPeeking && !targeted && !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(Color.accentColor)
            }
            Text(targeted ? L("Let go") : L("Drop here"))
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: targeted)
    }
}

enum ShelfLayout {
    /// Transparent room around the glass, for its grow and glow animations.
    static let margin: CGFloat = 12
    static let headerHeight: CGFloat = 22
    static let labelHeight: CGFloat = 30
    static let emptyHeight: CGFloat = 96

    /// Panel size for the shelf's content.
    static func size(itemCount: Int, side: CGFloat, maxHeight: CGFloat) -> CGSize {
        let width = side + 20 + 12
        let content = itemCount == 0
            ? emptyHeight
            : CGFloat(itemCount) * (side + labelHeight) + CGFloat(max(itemCount - 1, 0)) * 8 + 8
        let height = min(headerHeight + 6 + content + 16, maxHeight)
        return CGSize(width: max(width, 84) + margin * 2, height: height + margin * 2)
    }
}

// MARK: - Cells

/// Hosts the AppKit cell, which handles clicks, dragging out and the context menu.
private struct ShelfCell: NSViewRepresentable {
    let item: ShelfItem
    let side: CGFloat

    func makeNSView(context: Context) -> ShelfCellView {
        ShelfCellView(item: item, side: side)
    }

    func updateNSView(_ view: ShelfCellView, context: Context) {
        view.update(item: item, side: side)
    }
}

final class ShelfCellView: NSView, NSDraggingSource {
    private(set) var item: ShelfItem
    private let hosting: NSHostingView<ShelfCellContent>
    private var mouseDownPoint: NSPoint?
    private var side: CGFloat
    private var isHovered = false {
        didSet { if isHovered != oldValue { refresh() } }
    }

    init(item: ShelfItem, side: CGFloat) {
        self.item = item
        self.side = side
        hosting = NSHostingView(rootView: ShelfCellContent(item: item, side: side))
        super.init(frame: .zero)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        toolTip = item.title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { item.title }
    override func accessibilityPerformPress() -> Bool {
        ShelfActions.open([item])
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    private func refresh() {
        hosting.rootView = ShelfCellContent(item: item, side: side, isHovered: isHovered)
    }

    func update(item: ShelfItem, side: CGFloat) {
        self.item = item
        self.side = side
        hosting.rootView = ShelfCellContent(item: item, side: side, isHovered: isHovered)
        toolTip = item.title
    }

    /// The cell takes every click itself; the SwiftUI content only draws.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let store = ShelfStore.shared
        mouseDownPoint = event.locationInWindow
        window?.makeFirstResponder(window?.contentView)
        if event.modifierFlags.contains(.command) {
            if store.selection.contains(item.id) { store.selection.remove(item.id) } else { store.selection.insert(item.id) }
        } else if event.modifierFlags.contains(.shift), let last = store.selection.first,
                  let from = store.items.firstIndex(where: { $0.id == last }),
                  let to = store.items.firstIndex(where: { $0.id == item.id }) {
            store.selection = Set(store.items[min(from, to)...max(from, to)].map(\.id))
        } else if !store.selection.contains(item.id) {
            store.selection = [item.id]
        }
        if event.clickCount == 2 {
            ShelfActions.open([item])
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint,
              hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        let store = ShelfStore.shared
        let dragged = store.selection.contains(item.id)
            ? store.items.filter { store.selection.contains($0.id) }
            : [item]
        let draggingItems = dragged.flatMap { ShelfActions.pasteboardWriters(for: $0) }.enumerated().map { index, writer in
            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            let offset = CGFloat(min(index, 4)) * 4
            draggingItem.setDraggingFrame(bounds.offsetBy(dx: offset, dy: -offset), contents: snapshot())
            return draggingItem
        }
        guard !draggingItems.isEmpty else { return }
        draggedIDs = Set(dragged.map(\.id))
        let session = beginDraggingSession(with: draggingItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .stack
        // The item looks lifted off the shelf while it's being carried away.
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; animator().alphaValue = 0.35 }
    }

    override func rightMouseDown(with event: NSEvent) {
        let store = ShelfStore.shared
        if !store.selection.contains(item.id) { store.selection = [item.id] }
        let items = store.items.filter { store.selection.contains($0.id) }
        NSMenu.popUpContextMenu(ShelfActions.itemMenu(for: items), with: event, for: self)
    }

    private var draggedIDs: Set<UUID> = []

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        defer { draggedIDs = [] }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; animator().alphaValue = 1 }
        guard !operation.isEmpty, ShelfSettings.shared.removeAfterDragOut else { return }
        let store = ShelfStore.shared
        let removable = store.items.filter { draggedIDs.contains($0.id) && !$0.isLocked }.map(\.id)
        store.remove(Set(removable))
    }

    private func snapshot() -> NSImage {
        let image = NSImage(size: bounds.size)
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
            image.addRepresentation(rep)
        }
        return image
    }
}

/// What a cell shows: thumbnail (fanned out for stacks), badges and name.
private struct ShelfCellContent: View {
    let item: ShelfItem
    let side: CGFloat
    var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var store = ShelfStore.shared

    private var isSelected: Bool { store.selection.contains(item.id) }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                ShelfThumbnail(item: item, side: side)
                    .frame(width: side, height: side)
                badges
            }
            Text(item.title)
                .font(.system(size: 10))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 3)
                .background(isSelected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(height: ShelfLayout.labelHeight - 4, alignment: .top)
        }
        .padding(2)
        .background(isSelected ? Color.accentColor.opacity(0.18) : isHovered ? Color.primary.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 10))
        // Hover lifts the item a little, like an icon picked up off the shelf.
        .scaleEffect(isHovered && !reduceMotion ? 1.06 : 1)
        .shadow(color: .black.opacity(isHovered ? 0.25 : 0), radius: isHovered ? 6 : 0, y: isHovered ? 3 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
    }

    private var badges: some View {
        VStack {
            HStack {
                if item.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .padding(4)
                        .background(.regularMaterial, in: Circle())
                }
                Spacer()
                if item.isStack {
                    Text("\(item.urls.count)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            Spacer()
        }
        .frame(width: side + 8, height: side + 4)
    }
}

private struct ShelfThumbnail: View {
    let item: ShelfItem
    let side: CGFloat

    var body: some View {
        switch item.content {
        case .files(let files):
            ZStack {
                // A stack fans out its first files.
                ForEach(Array(files.prefix(3).enumerated().reversed()), id: \.offset) { index, file in
                    FileThumbnail(url: file.url, side: side * (files.count > 1 ? 0.82 : 1))
                        .rotationEffect(.degrees(files.count > 1 ? Double(index) * -7 : 0))
                        .offset(x: files.count > 1 ? CGFloat(index) * 4 : 0)
                }
            }
        case .text(let text):
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background)
                .overlay(alignment: .topLeading) {
                    Text(text)
                        .font(.system(size: max(side / 9, 7)))
                        .foregroundStyle(.primary)
                        .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.quaternary))
                .padding(side * 0.08)
        case .link:
            Image(systemName: "link.circle.fill")
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
                .padding(side * 0.18)
        case .color:
            Circle()
                .fill(Color(nsColor: item.nsColor ?? .gray))
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2))
                .shadow(radius: 2)
                .padding(side * 0.15)
        }
    }
}

private struct FileThumbnail: View {
    let url: URL
    let side: CGFloat
    @State private var thumbnails = ShelfThumbnails.shared

    var body: some View {
        Image(nsImage: thumbnails.image(for: url, side: side))
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
    }
}

/// Quick Look previews (or plain icons), generated once per file and size.
@MainActor
@Observable
final class ShelfThumbnails {
    static let shared = ShelfThumbnails()

    private var cache: [String: NSImage] = [:]
    @ObservationIgnored private var pending: Set<String> = []

    func image(for url: URL, side: CGFloat) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        guard ShelfSettings.shared.showPreviews else { return icon }
        let key = "\(url.path)#\(Int(side))"
        if let cached = cache[key] { return cached }
        if !pending.contains(key) {
            pending.insert(key)
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                       scale: scale, representationTypes: .all)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
                let image = representation?.nsImage
                DispatchQueue.main.async {
                    self?.pending.remove(key)
                    if let image { self?.cache[key] = image }
                }
            }
        }
        return icon
    }

    func clear() {
        cache.removeAll()
    }
}

/// A real blur of whatever is behind the shelf (the "frosted" part of the glass).
private struct ShelfBlurView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
