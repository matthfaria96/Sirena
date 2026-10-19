/// MacTilingDefaults.swift

import Foundation

/// Read / disable the user defaults values for the macOS built-in window tiling, added in macOS 15 Sequoia.
/// These are toggled in the Desktop & Dock System Settings Pane:
enum MacTilingDefaults: String {
    case tilingByEdgeDrag = "EnableTilingByEdgeDrag"
    case tilingOptionAccelerator = "EnableTilingOptionAccelerator"
    case tiledWindowMargins = "EnableTiledWindowMargins"
    case topTilingByEdgeDrag = "EnableTopTilingByEdgeDrag"
    
    var enabled: Bool {
        guard #available(macOS 15, *), let defaults = UserDefaults(suiteName: "com.apple.WindowManager")
        else {
            return false
        }
        
        if defaults.object(forKey: self.rawValue) == nil { // These are enabled by default
            return true
        }
        return defaults.bool(forKey: self.rawValue)
    }
    
    func disable() {
        guard let defaults = UserDefaults(suiteName: "com.apple.WindowManager")
        else {
            return
        }
        
        defaults.set(false, forKey: self.rawValue)
        defaults.synchronize()
    }
    
    static func openSystemSettings() {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.Desktop-Settings.extension")!)
    }
    
    /// Sirena is always the window manager: while its snapping is on, macOS's own tiling
    /// (edge drag, ⌥ accelerator and top edge) is switched off silently, so the two never
    /// fight and no conflict alert is shown. The user can turn it back on in System
    /// Settings → Desktop & Dock → Windows after disabling snapping in Sirena.
    static func checkForBuiltInTiling(skipIfAlreadyNotified: Bool) {
        guard #available(macOS 15, *), !Defaults.windowSnapping.userDisabled else { return }
        let isConflicting = tilingByEdgeDrag.enabled || tilingOptionAccelerator.enabled || topTilingByEdgeDrag.enabled
        guard isConflicting else { return }
        Logger.log("Disabling macOS tiling so Sirena manages window snapping.")
        disableMacTiling()
        Defaults.internalTilingNotified.enabled = true
    }

    private static func disableMacTiling() {
        tilingByEdgeDrag.disable()
        tilingOptionAccelerator.disable()
        topTilingByEdgeDrag.disable()
    }
}
