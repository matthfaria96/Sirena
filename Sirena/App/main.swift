/// main.swift

import Cocoa

// A child Sirena that only reads the Bluetooth batteries (ConnectedDevices.swift) and quits.
if CommandLine.arguments.contains(ConnectedDeviceReader.printClassicLevelsArgument) {
    ConnectedDeviceReader.printClassicLevelsAndExit()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}
