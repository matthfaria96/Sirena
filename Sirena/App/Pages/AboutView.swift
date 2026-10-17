/// AboutView.swift

import SwiftUI

struct AboutView: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return L("Version \(short) (\(build))")
    }

    private let libraries: [(name: String, author: String, license: String, url: String)] = [
        ("Fader", "pantafive", "MIT", "https://github.com/pantafive/fader"),
        ("MASShortcut", "Vadim Shpakovski", "BSD 2-Clause", "https://github.com/rxhanson/MASShortcut"),
        ("Defaults", "Sindre Sorhus", "MIT", "https://github.com/sindresorhus/Defaults"),
        ("KeyboardShortcuts", "Sindre Sorhus", "MIT", "https://github.com/sindresorhus/KeyboardShortcuts"),
        ("Settings", "Sindre Sorhus", "MIT", "https://github.com/sindresorhus/Settings"),
        ("Sauce", "Clipy Project", "MIT", "https://github.com/Clipy/Sauce"),
        ("Fuse", "Kiro Risk", "MIT", "https://github.com/krisk/fuse-swift"),
        ("SwiftHEXColors", "Thi Doãn", "MIT", "https://github.com/thii/SwiftHEXColors"),
        ("SwiftLog", "Apple Inc.", "Apache 2.0", "https://github.com/apple/swift-log"),
        ("HotKey", "Sam Soffes", "MIT", "https://github.com/soffes/HotKey"),
        ("SmoothGradient", "Ramon Torres", "MIT", "https://github.com/raymondjavaxx/SmoothGradient"),
        ("MediaRemoteAdapter", "Jonas van den Berg, Ethan Bills", L("See repository"), "https://github.com/ejbills/mediaremote-adapter")
    ]

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 128, height: 128)
                    Text("Sirena")
                        .font(.largeTitle.bold())
                    Text(version)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section(L("Built on")) {
                ForEach(ModuleID.allCases) { module in
                    credit(module.origin.name, module.origin.author, module.origin.license, module.origin.url) {
                        ModuleIcon(module: module, size: 22)
                    }
                }
            }

            Section(L("Libraries")) {
                ForEach(libraries, id: \.name) { library in
                    credit(library.name, library.author, library.license, library.url) { EmptyView() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func credit<Icon: View>(_ name: String, _ author: String, _ license: String, _ url: String,
                                    @ViewBuilder icon: () -> Icon) -> some View {
        LabeledContent {
            Link(license, destination: URL(string: url)!)
        } label: {
            HStack(spacing: 10) {
                icon()
                VStack(alignment: .leading) {
                    Text(name)
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
