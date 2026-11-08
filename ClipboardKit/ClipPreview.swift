import AppKit
import SwiftUI

// Sirena: what a copied item looks like at a glance (an image, a color, a link, files,
// code or plain text), for the preview tiles in the menu bar panel and the floating
// history panel. Worked out once per item from its contents, never from the network.

private func SL(_ key: String.LocalizationValue) -> String {
  String(localized: key, table: "Sirena", bundle: .main)
}

/// An sRGB color found in a copied text (`#8B5CF6`, `rgb(…)`, `hsl(…)`).
public struct ClipColor: Equatable, Sendable {
  public let red: Double
  public let green: Double
  public let blue: Double
  public let alpha: Double

  public var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

  public var hex: String {
    let parts = [red, green, blue].map { String(format: "%02X", Int(($0 * 255).rounded())) }
    let base = "#" + parts.joined()
    return alpha < 1 ? base + String(format: "%02X", Int((alpha * 255).rounded())) : base
  }

  public var rgb: String {
    let values = [red, green, blue].map { String(Int(($0 * 255).rounded())) }.joined(separator: ", ")
    return alpha < 1 ? "rgba(\(values), \(String(format: "%.2g", alpha)))" : "rgb(\(values))"
  }
}

public enum ClipPreview: Equatable, Sendable {
  case image
  case color(ClipColor)
  case link(URL)
  case files([URL])
  case code
  case text

  // MARK: - Detection

  static func detect(text: String, fileURLs: [URL], hasImage: Bool, isUniversalClipboard: Bool) -> ClipPreview {
    if hasImage, fileURLs.isEmpty || isUniversalClipboard { return .image }
    if !fileURLs.isEmpty { return .files(fileURLs) }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count <= 64, let color = parseColor(trimmed) { return .color(color) }
    if let url = parseLink(trimmed) { return .link(url) }
    if looksLikeCode(trimmed) { return .code }
    return .text
  }

  private static func parseLink(_ text: String) -> URL? {
    guard text.count <= 2_048, !text.contains(where: \.isWhitespace),
          let url = URL(string: text),
          let scheme = url.scheme?.lowercased(), ["http", "https", "ftp"].contains(scheme),
          let host = url.host(), !host.isEmpty
    else { return nil }
    return url
  }

  private static func looksLikeCode(_ text: String) -> Bool {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    guard lines.count >= 2 else { return false }
    let keywords = ["func ", "def ", "class ", "struct ", "const ", "let ", "var ", "import ",
                    "return ", "#include", "fn ", "=>", "</", "public ", "private "]
    var signals = 0
    for line in lines.prefix(60) {
      let trimmedLine = line.trimmingCharacters(in: .whitespaces)
      if let last = trimmedLine.last, [";", "{", "}", ")", ":"].contains(last) { signals += 1 }
      if line.hasPrefix("    ") || line.hasPrefix("\t") { signals += 1 }
      if keywords.contains(where: { trimmedLine.hasPrefix($0) || trimmedLine.contains(" \($0)") }) { signals += 1 }
    }
    return signals >= 3
  }

  // MARK: - Colors

  private static let hexPattern = try! NSRegularExpression(pattern: "^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")
  private static let rgbPattern = try! NSRegularExpression(
    pattern: #"^rgba?\(\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*(?:[,/]\s*([\d.]+)(%?))?\s*\)$"#,
    options: .caseInsensitive)
  private static let hslPattern = try! NSRegularExpression(
    pattern: #"^hsla?\(\s*([\d.]+)(?:deg)?\s*[, ]\s*([\d.]+)%\s*[, ]\s*([\d.]+)%\s*(?:[,/]\s*([\d.]+)(%?))?\s*\)$"#,
    options: .caseInsensitive)

  static func parseColor(_ text: String) -> ClipColor? {
    let range = NSRange(text.startIndex..., in: text)
    func groups(_ regex: NSRegularExpression) -> [String?]? {
      guard let match = regex.firstMatch(in: text, range: range) else { return nil }
      return (1..<match.numberOfRanges).map { index in
        Range(match.range(at: index), in: text).map { String(text[$0]) }
      }
    }
    func alpha(_ value: String?, percent: String?) -> Double {
      guard let value, let number = Double(value) else { return 1 }
      return min(max(percent == "%" ? number / 100 : number, 0), 1)
    }

    if let parts = groups(hexPattern), var hex = parts[0] {
      if hex.count <= 4 { hex = hex.map { "\($0)\($0)" }.joined() }
      guard let value = UInt64(hex, radix: 16) else { return nil }
      let hasAlpha = hex.count == 8
      let rgb = hasAlpha ? value >> 8 : value
      return ClipColor(red: Double((rgb >> 16) & 0xFF) / 255,
                       green: Double((rgb >> 8) & 0xFF) / 255,
                       blue: Double(rgb & 0xFF) / 255,
                       alpha: hasAlpha ? Double(value & 0xFF) / 255 : 1)
    }
    if let parts = groups(rgbPattern) {
      let channels = parts.prefix(3).compactMap { $0.flatMap(Double.init) }
      guard channels.count == 3, channels.allSatisfy({ $0 <= 255 }) else { return nil }
      return ClipColor(red: channels[0] / 255, green: channels[1] / 255, blue: channels[2] / 255,
                       alpha: alpha(parts[3], percent: parts[4]))
    }
    if let parts = groups(hslPattern) {
      let values = parts.prefix(3).compactMap { $0.flatMap(Double.init) }
      guard values.count == 3, values[1] <= 100, values[2] <= 100 else { return nil }
      let hue = values[0].truncatingRemainder(dividingBy: 360) / 360
      let saturation = values[1] / 100
      let lightness = values[2] / 100
      // HSL → HSB, which NSColor understands.
      let brightness = lightness + saturation * min(lightness, 1 - lightness)
      let hsbSaturation = brightness == 0 ? 0 : 2 * (1 - lightness / brightness)
      let color = NSColor(hue: hue, saturation: hsbSaturation, brightness: brightness, alpha: 1)
      guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
      return ClipColor(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent,
                       alpha: alpha(parts[3], percent: parts[4]))
    }
    return nil
  }

  // MARK: - Shown text

  /// A short line about what it is (shown under the title).
  public var caption: String? {
    switch self {
    case .image: return SL("Image")
    case .color(let color): return color.hex
    case .link(let url): return url.host()?.replacingOccurrences(of: "www.", with: "")
    case .files(let urls): return urls.count == 1 ? SL("File") : SL("\(urls.count) files")
    case .code: return SL("Code")
    case .text: return nil
    }
  }
}

// MARK: - Tile

/// The square preview at the start of a history row, with the source app's icon in a corner.
public struct ClipPreviewTile: View {
  let preview: ClipPreview
  let thumbnail: NSImage?
  let appIcon: NSImage?
  let size: CGFloat

  public init(preview: ClipPreview, thumbnail: NSImage?, appIcon: NSImage?, size: CGFloat = 36) {
    self.preview = preview
    self.thumbnail = thumbnail
    self.appIcon = appIcon
    self.size = size
  }

  private var radius: CGFloat { size * 0.24 }

  public var body: some View {
    content
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
      )
      .overlay(alignment: .bottomTrailing) {
        if let appIcon, showsAppBadge {
          Image(nsImage: appIcon)
            .resizable()
            .frame(width: size * 0.46, height: size * 0.46)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            .offset(x: size * 0.12, y: size * 0.12)
        }
      }
      .padding(.trailing, showsAppBadge && appIcon != nil ? size * 0.1 : 0)
      .padding(.bottom, showsAppBadge && appIcon != nil ? size * 0.1 : 0)
      .accessibilityHidden(true)
  }

  /// Text items show the app icon itself, big; everything else gets it as a badge.
  private var showsAppBadge: Bool { preview != .text }

  @ViewBuilder
  private var content: some View {
    switch preview {
    case .image:
      if let thumbnail {
        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
      } else {
        symbolTile("photo", tint: .secondary)
      }
    case .color(let color):
      ZStack {
        // A checkerboard shows through see-through colors.
        Checkerboard().opacity(color.alpha < 1 ? 1 : 0)
        color.color
      }
    case .link:
      symbolTile("link", tint: .blue)
    case .files(let urls):
      ZStack {
        Rectangle().fill(.quaternary.opacity(0.5))
        if let first = urls.first {
          Image(nsImage: NSWorkspace.shared.icon(forFile: first.path(percentEncoded: false)))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(size * 0.08)
        }
      }
    case .code:
      symbolTile("chevron.left.forwardslash.chevron.right", tint: .purple)
    case .text:
      if let appIcon {
        Image(nsImage: appIcon).resizable().aspectRatio(contentMode: .fit).padding(size * 0.06)
      } else {
        symbolTile("text.alignleft", tint: .secondary)
      }
    }
  }

  private func symbolTile(_ symbol: String, tint: Color) -> some View {
    ZStack {
      Rectangle().fill(tint.opacity(0.14))
      Image(systemName: symbol)
        .font(.system(size: size * 0.42, weight: .semibold))
        .foregroundStyle(tint)
    }
  }
}

private struct Checkerboard: View {
  var body: some View {
    Canvas { context, size in
      let cell: CGFloat = 5
      for row in 0..<Int(size.height / cell) + 1 {
        for column in 0..<Int(size.width / cell) + 1 where (row + column).isMultiple(of: 2) {
          context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                       with: .color(.gray.opacity(0.35)))
        }
      }
    }
    .background(.white)
  }
}

// MARK: - Detail (hover preview)

/// The larger preview shown when the pointer rests on a row.
public struct ClipPreviewDetail: View {
  let entry: ClipboardEntry
  let thumbnail: NSImage?
  let fullText: String

  public init(entry: ClipboardEntry, thumbnail: NSImage?, fullText: String) {
    self.entry = entry
    self.thumbnail = thumbnail
    self.fullText = fullText
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      content
      footer
    }
    .padding(12)
    .frame(width: 300, alignment: .leading)
  }

  @ViewBuilder
  private var content: some View {
    switch entry.preview {
    case .image:
      if let thumbnail {
        Image(nsImage: thumbnail)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: 276, maxHeight: 220)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .frame(maxWidth: .infinity)
      } else {
        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
      }
    case .color(let color):
      ClipPreviewTile(preview: entry.preview, thumbnail: nil, appIcon: nil, size: 64)
        .frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .leading, spacing: 3) {
        Text(color.hex)
        Text(color.rgb)
      }
      .font(.system(.callout, design: .monospaced))
      .textSelection(.enabled)
    case .link(let url):
      Label(url.host() ?? url.absoluteString, systemImage: "link")
        .font(.headline)
        .lineLimit(1)
      Text(url.absoluteString)
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(4)
        .truncationMode(.middle)
        .textSelection(.enabled)
    case .files(let urls):
      VStack(alignment: .leading, spacing: 6) {
        ForEach(urls.prefix(6), id: \.self) { url in
          HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
              .resizable()
              .frame(width: 22, height: 22)
            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
          }
        }
        if urls.count > 6 {
          Text(SL("and \(urls.count - 6) more")).font(.caption).foregroundStyle(.secondary)
        }
      }
    case .code, .text:
      ScrollView {
        Text(fullText)
          .font(entry.preview == .code ? .system(.callout, design: .monospaced) : .callout)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
      }
      .frame(maxHeight: 220)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var footer: some View {
    HStack(spacing: 4) {
      if let app = entry.appName {
        Text(app)
        Text("·")
      }
      Text(entry.lastCopied, format: .relative(presentation: .named))
      if entry.copies > 1 {
        Text("·")
        Text(SL("copied \(entry.copies) times"))
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .lineLimit(1)
  }
}
