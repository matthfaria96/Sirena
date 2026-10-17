/// PinPanels.swift
///
/// The two panels that make up a pinned window: the floating copy of the window and
/// the pin control over its traffic lights.

import AppKit

/// Borderless floating panel showing the live copy of a pinned window.
final class PinMirrorPanel: NSPanel {
    let contentLayer = CALayer()
    /// Pointer pressed or scrolled on the copy: the real window should take over.
    var onActivate: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        let view = PinMirrorView(layer: contentLayer)
        view.onActivate = { [weak self] in self?.onActivate?() }
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PinMirrorView: NSView {
    var onActivate: (() -> Void)?

    init(layer contentLayer: CALayer) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        contentLayer.contentsGravity = .resize
        contentLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(contentLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.sublayers?.first?.frame = bounds
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onActivate?() }
    override func rightMouseDown(with event: NSEvent) { onActivate?() }
    override func scrollWheel(with event: NSEvent) { onActivate?() }
}

/// The pin control laid over the traffic lights of a pinned window. The copy's own
/// traffic lights can't be clicked, so this takes their place: it opens a menu to
/// unpin, minimize, maximize or go full screen.
final class PinControlPanel: NSPanel {
    var onClick: ((NSView) -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 64, height: 24),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        let view = PinControlView(frame: NSRect(x: 0, y: 0, width: 64, height: 24))
        view.autoresizingMask = [.width, .height]
        view.onClick = { [weak self, weak view] in
            guard let view else { return }
            self?.onClick?(view)
        }
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PinControlView: NSView {
    var onClick: (() -> Void)?

    private let background = NSVisualEffectView()
    private let stack: NSStackView

    override init(frame frameRect: NSRect) {
        let pin = NSImageView(image: NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))!)
        pin.contentTintColor = .white
        let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 8, weight: .bold))!)
        chevron.contentTintColor = .white.withAlphaComponent(0.8)
        stack = NSStackView(views: [pin, chevron])
        stack.spacing = 4
        super.init(frame: frameRect)

        background.material = .hudWindow
        background.appearance = NSAppearance(named: .vibrantDark)
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.masksToBounds = true
        background.autoresizingMask = [.width, .height]
        background.frame = bounds
        addSubview(background)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        toolTip = L("Pinned window")
        setAccessibilityRole(.menuButton)
        setAccessibilityLabel(L("Pinned window"))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        background.layer?.cornerRadius = bounds.height / 2
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onClick?() }
}

/// Menu icons drawn like the window's traffic lights, so the menu matches macOS.
enum TrafficLightIcon {
    case close, minimize, zoom

    var image: NSImage {
        let (color, symbol): (NSColor, String) = switch self {
        case .close: (.systemRed, "xmark")
        case .minimize: (.systemYellow, "minus")
        case .zoom: (.systemGreen, "plus")
        }
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            color.setFill()
            circle.fill()
            color.shadow(withLevel: 0.25)?.setStroke()
            circle.lineWidth = 0.5
            circle.stroke()
            let glyphSize: CGFloat = self == .close ? 7 : 8
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: glyphSize, weight: .black)
                    .applying(.init(paletteColors: [NSColor.black.withAlphaComponent(0.55)]))) {
                let glyphRect = NSRect(x: rect.midX - glyph.size.width / 2, y: rect.midY - glyph.size.height / 2,
                                       width: glyph.size.width, height: glyph.size.height)
                glyph.draw(in: glyphRect)
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// Menu item running a closure, for menus built by objects that aren't NSObjects.
final class PinMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, image: NSImage? = nil, state: NSControl.StateValue = .off, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        self.state = state
        if let image {
            self.image = image
        } else if let symbol {
            self.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        if self.image != nil, #available(macOS 27.0, *) {
            preferredImageVisibility = .visible
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func run() { handler() }
}
