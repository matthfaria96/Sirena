/// MediaWidgetPreview.swift
///
/// Illustration for "Music player in previews" (Settings › Windows & Dock › Dock): the pointer on a
/// music app in the Dock and, above it, the window preview with the embedded player, so people see
/// what the switch does before turning it on. Drawn in SwiftUI, so it follows light/dark mode.

import SwiftUI

struct MediaWidgetPreview: View {
    private let accent = LinearGradient(colors: [Color(red: 1, green: 0.42, blue: 0.62), Color(red: 0.55, green: 0.36, blue: 0.96)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        VStack(spacing: 8) {
            previewCard
            dock
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Example: the Dock preview of a music app with playback controls"))
    }

    /// A prévia da janela, com o player no lugar do conteúdo.
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach([Color.red, .yellow, .green], id: \.self) { color in
                    Circle().fill(color.opacity(0.85)).frame(width: 7, height: 7)
                }
                Text("Music")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(accent)
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "music.note").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(.primary.opacity(0.55)).frame(width: 92, height: 7)
                    Capsule().fill(.primary.opacity(0.25)).frame(width: 60, height: 6)
                    HStack(spacing: 14) {
                        Image(systemName: "backward.fill")
                        Image(systemName: "play.fill").font(.system(size: 13))
                        Image(systemName: "forward.fill")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.primary.opacity(0.8))
                }
            }
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.14))
                Capsule().fill(accent).frame(width: 74)
            }
            .frame(height: 3)
        }
        .padding(10)
        .frame(width: 200, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    /// O Dock, com o cursor sobre o app de música.
    private var dock: some View {
        HStack(spacing: 8) {
            appTile(Color.blue.opacity(0.75), symbol: "safari.fill")
            appTile(nil, symbol: "music.note")
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                        .shadow(color: .black.opacity(0.25), radius: 1)
                        .offset(x: 8, y: 8)
                }
            appTile(Color.gray.opacity(0.6), symbol: "folder.fill")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.08)))
    }

    private func appTile(_ color: Color?, symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(accent))
            .frame(width: 26, height: 26)
            .overlay(Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white))
    }
}

#Preview {
    MediaWidgetPreview().padding().frame(width: 320)
}
