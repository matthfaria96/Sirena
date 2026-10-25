// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint; Sirena port.

import AppKit
import SwiftUI

/// The preference keys of the mixer. Vorssaint's keys, prefixed so they never
/// meet another module's registered defaults in the shared domain.
enum SirenaMixerDefaultsKey {
    static let appVolumes = "sirenaMixer.appVolumes"                  // [bundle id: 0...2 slider position]
    static let appOutputDevices = "sirenaMixer.appOutputDevices"      // [bundle id: audio device UID]
    static let mixerShowFinder = "sirenaMixer.showFinder"
    static let mixerAppArrangement = "sirenaMixer.appArrangement"
    static let mixerHideInactiveApps = "sirenaMixer.hideInactiveApps"
    /// Menu bar sliders: Liquid Glass (default) or the standard macOS slider.
    static let glassSliders = "sirenaMixer.glassSliders"
    static let mixerHiddenApps = "sirenaMixer.hiddenApps"             // [persistence id: display name]
    static let mixerLowerVolumeOnHeadphonesDisconnect = "sirenaMixer.lowerVolumeOnHeadphonesDisconnect"
    static let mixerHeadphonesDisconnectVolumePercent = "sirenaMixer.headphonesDisconnectVolumePercent"
    static let preferredInputDevice = "sirenaMixer.preferredInputDevice" // audio input device UID
    /// Liquid Glass sliders. Off by default, as in Vorssaint.
}

/// Sanitizers and defaults the mixer reads, from Vorssaint's `Defaults`.
enum SirenaMixerDefaults {
    static func sanitizedAppVolume(_ volume: Double) -> Double {
        guard volume.isFinite else { return 1 }
        return min(max(volume, 0), 2)
    }

    /// The volume the speakers are set to when headphones disconnect. At zero
    /// the lowering also turns their mute on.
    static let minimumMixerHeadphonesDisconnectVolumePercent = 0
    static let defaultMixerHeadphonesDisconnectVolumePercent = 25

    static func sanitizedMixerHeadphonesDisconnectVolumePercent(_ percent: Int) -> Int {
        min(max(percent, minimumMixerHeadphonesDisconnectVolumePercent), 100)
    }

    /// The stored level, or the default when nothing was ever saved (Vorssaint
    /// registers that default; Sirena reads it here instead).
    static var headphonesDisconnectVolumePercent: Int {
        let stored = UserDefaults.standard.object(
            forKey: SirenaMixerDefaultsKey.mixerHeadphonesDisconnectVolumePercent) as? Int
        return sanitizedMixerHeadphonesDisconnectVolumePercent(
            stored ?? defaultMixerHeadphonesDisconnectVolumePercent)
    }

    /// Whether the Finder keeps a row while silent. Defaults to true.
    static var showFinder: Bool {
        UserDefaults.standard.object(forKey: SirenaMixerDefaultsKey.mixerShowFinder) as? Bool ?? true
    }

    static func sanitizedAppOutputDeviceUID(_ value: Any?) -> String? {
        SirenaMixerRoutingSupport.sanitizedDeviceUID(value)
    }

    static func sanitizedAppOutputDevices(_ raw: [String: Any]) -> [String: String] {
        SirenaMixerRoutingSupport.sanitizedRouteMap(raw)
    }

    static func sanitizedPreferredInputDeviceUID(_ value: Any?) -> String? {
        SirenaMixerRoutingSupport.sanitizedDeviceUID(value)
    }

    /// The private aggregate each tap renders through. Listed to this process
    /// only, and skipped by every device list below by name.
    static let aggregateDeviceName = "Sirena Mixer"

    /// Devices this process creates for its own plumbing (this mixer's
    /// aggregates, the island's level reader and SoundKit's Fader taps). They
    /// carry a tapped app's audio, not a real output or microphone, so the
    /// pickers never offer them.
    private static let ownDeviceNames: Set<String> = [aggregateDeviceName, "Sirena Island Levels"]

    static func isOwnDevice(name: String) -> Bool {
        ownDeviceNames.contains(name) || name.hasPrefix("Fader ")
    }
}

/// Vorssaint's panel colours, darkened in Light Mode for contrast.
enum SirenaMixerColor {
    static func green(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.00, green: 0.44, blue: 0.18) : .green
    }

    static func red(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.68, green: 0.08, blue: 0.10) : .red
    }

    static func orange(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.68, green: 0.30, blue: 0.00) : .orange
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.38) : Color.white.opacity(0.075)
    }

    static func border(for scheme: ColorScheme) -> Color {
        let raised = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return scheme == .light
            ? Color.black.opacity(raised ? 0.24 : 0.09)
            : Color.white.opacity(raised ? 0.28 : 0.11)
    }
}

extension View {
    /// Vorssaint's rounded panel card (`panelCard(interactive: false)`).
    func sirenaMixerCard() -> some View {
        modifier(SirenaMixerCardModifier())
    }
}

private struct SirenaMixerCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SirenaMixerColor.cardFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(SirenaMixerColor.border(for: colorScheme), lineWidth: 0.7)
            )
    }
}

/// Vorssaint's pt-BR strings for the mixer, hardcoded (the user's language).
enum SirenaMixerStrings {
    static let section = "Mixer de volume"
    static let empty = "Apps que usam áudio aparecem aqui"
    static let unavailable = "Disponível a partir do macOS 14.4"
    static let permissionBody = "Para ajustar o volume por app, permita “Gravação de Tela e Áudio do Sistema” nos Ajustes do Sistema. O áudio nunca é gravado."
    static let permissionOpenSettings = "Abrir Ajustes do Sistema…"
    static let resetTooltip = "Voltar para 100%"
    static let outputDefault = "Padrão"
    static let outputCurrent = "atual"
    static let outputUnavailable = "Saída indisponível"
    static let outputFallback = "Usando o padrão até esse dispositivo voltar."
    static let bypassedCaption = "Este app controla o próprio áudio."
    static let outputTooltip = "Escolher saída"
    static let systemOutputTitle = "Saída"
    static let systemOutputNoDevices = "Nenhuma saída encontrada"
    static let systemOutputTooltip = "Escolher saída do sistema"
    static let systemOutputErrorFormat = "Não foi possível trocar: %@"
    static let soundEffectsOutputTitle = "Sons do sistema"
    static let soundEffectsOutputTooltip = "Escolher onde alertas e efeitos sonoros tocam"
    static let lowerOnHeadphonesDisconnect = "Baixar volume ao desconectar fones"
    static let lowerOnHeadphonesDisconnectCaption = "Ajusta a saída quando fones com fio ou Bluetooth desconectam."
    static let headphonesDisconnectVolume = "Volume ao desconectar"
    static let inputTitle = "Microfone"
    static let inputNoDevices = "Nenhum microfone encontrado"
    static let inputUnavailable = "Microfone indisponível"
    static let inputFallback = "Usando o padrão até esse microfone voltar."
    static let inputTooltip = "Escolher microfone"
    static let inputErrorFormat = "Não foi possível trocar: %@"
    static let visibleApps = "Apps na lista"
    static let allShown = "Todos"
    static let hiddenCountLabel = "Escondidos"
    static let hideFromList = "Esconder da lista"
    static let options = "Opções"
    static let outputTab = "Saída"
    static let micTab = "Microfone"
    static let collapse = "Recolher"
    static let expandHint = "Dispositivos e volume de cada app"
    static let collapseAccessibility = "Recolher o mixer"
    static let expandAccessibility = "Expandir o mixer"
    static let hideInactiveApps = "Ocultar apps inativos"
    static let pin = "Fixar no topo"
    static let unpin = "Desafixar"
    static let moveUp = "Mover para cima"
    static let moveDown = "Mover para baixo"
    static let arrange = "Segure Command e arraste para reorganizar"
}

/// The mixer's engine as one object to start and stop: per-app volume and
/// routing (`SirenaAppVolumeMixer`) and the microphone picker
/// (`SirenaMixerInputManager`). `SirenaMixerView` starts it lazily on appear;
/// call `stop()` when the app quits so every tapped app is handed back to its
/// untouched output and an overridden microphone is restored.
@MainActor
final class SirenaMixer {
    static let shared = SirenaMixer()

    private(set) var isRunning = false

    private init() {}

    func start() {
        // Showcase mode (site screenshots) never touches the Mac's audio.
        guard !Showcase.isActive else { return }
        isRunning = true
        SirenaAppVolumeMixer.shared.start()
        SirenaMixerInputManager.shared.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        SirenaAppVolumeMixer.shared.stop()
        SirenaMixerInputManager.shared.stop()
    }

    /// Opens Privacy & Security › Screen & System Audio Recording.
    func openAudioCaptureSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
        NSWorkspace.shared.open(url)
    }
}
