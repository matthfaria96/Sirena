import Carbon
import Cocoa
import Defaults

func askUserToRestartApplication() {
    MessageUtil.showAlert(
        title: String(localized: "Restart required"),
        message: String(localized: "Please restart the application to apply your changes. Click OK to quit the app."),
        actions: [.ok, .cancel],
        completion: { result in
            if result == .ok {
                Task { @MainActor in DockController.shared.restartApp() }
            }
        }
    )
}

func getWindowSize() -> CGSize {
    let width = Defaults[.previewWidth]
    let height = Defaults[.previewHeight]
    return CGSize(width: width, height: height)
}

// Measure string length in px
func measureString(_ string: String, fontSize: CGFloat, fontWeight: NSFont.Weight = .regular) -> CGSize {
    let font = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let attributedString = NSAttributedString(string: string, attributes: attributes)
    let size = attributedString.size()
    return size
}
