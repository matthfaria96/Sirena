/// AboutView.swift
///
/// The end of Geral: centered and quiet, like About This Mac. The open-source projects
/// Sirena is built from are named in one line, with their licenses a click away.

import SwiftUI

struct AboutBlock: View {
    @State private var showsLicenses = false

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return L("Version \(short) (\(build))")
    }

    var body: some View {
        VStack(spacing: 0) {
            Image("SirenaIcon")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                .padding(.bottom, 16)
            Text("Sirena")
                .font(.title.weight(.semibold))
            Text(version)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)

            Text(L("Sirena brings together what you use every day on the Mac: windows, the Dock, ⌘ Tab, the clipboard, a shelf for files, the notch and quick controls in the menu bar."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 440)
                .padding(.top, 20)

            Text(L("Built on open-source projects: \(AboutBlock.projectNames)."))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .padding(.top, 12)

            Button(L("Open-source licenses")) { showsLicenses = true }
                .buttonStyle(.link)
                .font(.caption)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .sheet(isPresented: $showsLicenses) { LicensesSheet() }
    }

    /// The apps Sirena's features come from, once each.
    static var projectNames: String {
        var seen = Set<String>()
        let names = ModuleID.allCases.map(\.origin.name).filter { seen.insert($0).inserted }
        return names.formatted(.list(type: .and))
    }
}

/// Every project and library with its license and a link, in a plain list.
private struct LicensesSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Entry: Identifiable {
        let name: String
        let author: String
        let license: String
        let url: String
        var id: String { name }
    }

    private var entries: [Entry] {
        var seen = Set<String>()
        let apps = ModuleID.allCases.compactMap { module -> Entry? in
            let origin = module.origin
            guard seen.insert(origin.name).inserted else { return nil }
            return Entry(name: origin.name, author: origin.author, license: origin.license, url: origin.url)
        }
        return apps + [
            Entry(name: "MASShortcut", author: "Vadim Shpakovski", license: "BSD 2-Clause", url: "https://github.com/rxhanson/MASShortcut"),
            Entry(name: "Defaults", author: "Sindre Sorhus", license: "MIT", url: "https://github.com/sindresorhus/Defaults"),
            Entry(name: "KeyboardShortcuts", author: "Sindre Sorhus", license: "MIT", url: "https://github.com/sindresorhus/KeyboardShortcuts"),
            Entry(name: "Settings", author: "Sindre Sorhus", license: "MIT", url: "https://github.com/sindresorhus/Settings"),
            Entry(name: "Sauce", author: "Clipy Project", license: "MIT", url: "https://github.com/Clipy/Sauce"),
            Entry(name: "Fuse", author: "Kiro Risk", license: "MIT", url: "https://github.com/krisk/fuse-swift"),
            Entry(name: "SwiftHEXColors", author: "Thi Doãn", license: "MIT", url: "https://github.com/thii/SwiftHEXColors"),
            Entry(name: "SwiftLog", author: "Apple Inc.", license: "Apache 2.0", url: "https://github.com/apple/swift-log"),
            Entry(name: "HotKey", author: "Sam Soffes", license: "MIT", url: "https://github.com/soffes/HotKey"),
            Entry(name: "SmoothGradient", author: "Ramon Torres", license: "MIT", url: "https://github.com/raymondjavaxx/SmoothGradient"),
            Entry(name: "MediaRemoteAdapter", author: "Jonas van den Berg, Ethan Bills", license: L("See repository"),
                  url: "https://github.com/ejbills/mediaremote-adapter")
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("Open-source licenses")).font(.headline)
                Spacer()
                Button(L("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            List(entries) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                        Text(entry.author).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let url = URL(string: entry.url) {
                        Link(entry.license, destination: url).font(.caption)
                    } else {
                        Text(entry.license).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
        }
        .frame(width: 460, height: 480)
    }
}
