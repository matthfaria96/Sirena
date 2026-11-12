/// LogViewer.swift

import Cocoa

class Logger {
    
    static var logging = false
    
    static private var logWindowController: LogWindowController?

    static func log(_ string: String) {
        if logging {
            logWindowController?.append(string)
        }
    }
}

class LogWindowController: NSWindowController, NSWindowDelegate {

    @IBAction func clearClicked(_ sender: Any) {
        (contentViewController as? LogViewController)?.clear()
    }
    
    func append(_ string: String) {
        let datestamp = String(NSDate().timeIntervalSince1970)
        (contentViewController as? LogViewController)?.append(datestamp + ": " + string + "\n")
    }
    
    func windowWillClose(_ notification: Notification) {
        Logger.logging = false
        clearClicked(self)
    }
}

extension LogWindowController {
    // MARK: Storyboard instantiation
}

class LogViewController: NSViewController {
    
    @IBOutlet var textView: NSTextView!
    
    let font = NSFont(name:"Monaco", size: 10) ?? NSFont.systemFont(ofSize: 10)
    
    let textColorAttribute =
        [NSAttributedString.Key.foregroundColor: NSColor.textColor,
         NSAttributedString.Key.font: NSFont(name:"Monaco", size: 10) ?? NSFont.systemFont(ofSize: 10)]
            
            as [NSAttributedString.Key: Any]
    
    func append(_ string: String) {
        let smartScroll = self.textView.visibleRect.maxY == self.textView.bounds.maxY
        
        textView.textStorage?.append(NSAttributedString(string: string, attributes: textColorAttribute))
        
        if smartScroll{
            textView.scrollToEndOfDocument(self)
        }
    }

    func clear() {
        textView.string = ""
    }
    
    override func viewDidLoad() {
        textView.isEditable = false
    }
    
}

class KeyDownTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(NSEvent.ModifierFlags.command) {
            switch event.charactersIgnoringModifiers! {
            case "w":
                self.window?.close()
            case "h":
                self.window?.orderOut(self)
            default:
                super.keyDown(with: event)
            }
        } else {
            super.keyDown(with: event)
        }
    }
}
