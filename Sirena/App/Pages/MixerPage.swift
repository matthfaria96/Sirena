/// MixerPage.swift
///
/// Mixer de som: Vorssaint's volume mixer as a page — the Mac's output and volume, the
/// system sounds, the microphone, every app's volume and output, and its options.

import SwiftUI

struct MixerPage: View {
    var body: some View {
        ModulePage(module: .mixer, tabs: [
            PageTab("mixer", L("Mixer")) {
                ScrollView {
                    SirenaMixerView(showsTitle: false, width: 460)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
                .scrollIndicators(.automatic)
            }
        ])
    }
}
