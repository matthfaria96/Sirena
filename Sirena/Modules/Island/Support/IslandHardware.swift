// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Written for Sirena's port of the Dynamic Island. Vorssaint drives these
// levels through its own mixer, brightness and microphone services; Sirena
// has none of them, so the island reads and sets the system's own here.

import AppKit
import Combine
import CoreAudio
import IOKit
import AudioToolbox
import MASShortcut

extension NSScreen {
    /// The screen under the pointer, falling back to the main one.
    static var islandWithMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main
    }

    /// The display that owns the menu bar, the one at the coordinate origin.
    static var islandWithMenuBar: NSScreen? {
        screens.first { $0.frame.origin == .zero } ?? screens.first
    }
}

// MARK: - Shortcut

/// The island's global shortcut, recorded with MASShortcut like Sirena's others.
final class IslandHotkey {
    let defaultsKey: String
    var onPress: (() -> Void)?
    private var bound = false

    init(defaultsKey: String) { self.defaultsKey = defaultsKey }

    func sync(enabled: Bool) {
        guard enabled != bound else { return }
        guard enabled else { unregister(); return }
        guard let binder = MASShortcutBinder.shared() else { return }
        binder.bindingOptions = [NSBindingOption.valueTransformerName: MASDictionaryTransformerName]
        binder.bindShortcut(withDefaultsKey: defaultsKey) { [weak self] in self?.onPress?() }
        bound = true
    }

    func unregister() {
        guard bound else { return }
        MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: defaultsKey)
        bound = false
    }
}

// MARK: - Core Audio helpers

private enum IslandCoreAudio {
    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, as value: T) -> T? {
        var address = address(selector, scope, element)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var result = value
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr else { return nil }
        return result
    }

    @discardableResult
    static func write<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, _ value: T) -> Bool {
        var address = address(selector, scope, element)
        guard AudioObjectHasProperty(object, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(object, &address, &settable) == noErr, settable.boolValue else { return false }
        var data = value
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &data) == noErr
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() as String? else { return nil }
        return string
    }

    static func devices() -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    static func channelCount(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func defaultDevice(input: Bool) -> AudioObjectID? {
        let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        let device = read(AudioObjectID(kAudioObjectSystemObject), selector, as: AudioObjectID(0)) ?? 0
        return device == 0 ? nil : device
    }

    /// The device's level: its virtual main volume, or the first channel's.
    static func volume(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Double? {
        if let value = read(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope, as: Float32(0)) {
            return Double(value)
        }
        for element in [kAudioObjectPropertyElementMain, 1] {
            if let value = read(device, kAudioDevicePropertyVolumeScalar, scope: scope, element: element, as: Float32(0)) {
                return Double(value)
            }
        }
        return nil
    }

    @discardableResult
    static func setVolume(_ device: AudioObjectID, scope: AudioObjectPropertyScope, _ volume: Double) -> Bool {
        let value = Float32(min(1, max(0, volume)))
        if write(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope, value) { return true }
        var done = false
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
            done = write(device, kAudioDevicePropertyVolumeScalar, scope: scope, element: element, value) || done
        }
        return done
    }

    static func muted(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool? {
        read(device, kAudioDevicePropertyMute, scope: scope, as: UInt32(0)).map { $0 != 0 }
    }

    @discardableResult
    static func setMuted(_ device: AudioObjectID, scope: AudioObjectPropertyScope, _ muted: Bool) -> Bool {
        write(device, kAudioDevicePropertyMute, scope: scope, UInt32(muted ? 1 : 0))
    }
}

/// Listens to a set of Core Audio properties on the main queue and forgets
/// them together.
private final class IslandAudioListeners {
    private var installed: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func add(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
             element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
             _ handler: @escaping () -> Void) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(object, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        if AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr {
            installed.append((object, address, block))
        }
    }

    func removeAll() {
        for (object, address, block) in installed {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
        }
        installed.removeAll()
    }
}

// MARK: - Output

/// The system output: its level and mute, and the outputs to choose from.
final class IslandAudioOutput: ObservableObject {
    static let shared = IslandAudioOutput()

    enum PriorityTier { case builtIn, hardware, virtual }

    struct Device: Identifiable, Equatable {
        let objectID: AudioObjectID
        let uid: String
        let name: String
        let isHeadphones: Bool
        let priorityTier: PriorityTier
        let canBeDefaultOutput: Bool
        var id: String { uid }
    }

    @Published private(set) var systemOutputVolume: Double?
    @Published private(set) var systemOutputMuted: Bool?
    @Published private(set) var outputDevices: [Device] = []
    @Published private(set) var currentOutputDeviceUID: String?
    @Published private(set) var outputSwitchError: String?

    private let systemListeners = IslandAudioListeners()
    private let deviceListeners = IslandAudioListeners()
    private var deviceID: AudioObjectID?

    private init() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        systemListeners.add(system, kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in self?.reloadDevice() }
        systemListeners.add(system, kAudioHardwarePropertyDevices) { [weak self] in self?.reloadDevices() }
        reloadDevices()
        reloadDevice()
    }

    private func reloadDevices() {
        let next = IslandCoreAudio.devices().compactMap(Self.device(_:))
        if next != outputDevices { outputDevices = next }
    }

    private static func device(_ id: AudioObjectID) -> Device? {
        guard IslandCoreAudio.channelCount(id, scope: kAudioObjectPropertyScopeOutput) > 0,
              let uid = IslandCoreAudio.string(id, kAudioDevicePropertyDeviceUID) else { return nil }
        let name = IslandCoreAudio.string(id, kAudioObjectPropertyName) ?? uid
        let transport = IslandCoreAudio.read(id, kAudioDevicePropertyTransportType, as: UInt32(0)) ?? 0
        let tier: PriorityTier
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: tier = .builtIn
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate,
             kAudioDeviceTransportTypeAirPlay, kAudioDeviceTransportTypeUnknown: tier = .virtual
        default: tier = .hardware
        }
        let lowered = name.lowercased()
        let headphones: Bool = transport == kAudioDeviceTransportTypeBluetooth
            && ["airpods", "headphone", "beats", "buds", "headset"].contains { lowered.contains($0) }
        let canDefaultValue: UInt32? = IslandCoreAudio.read(id, kAudioDevicePropertyDeviceCanBeDefaultDevice,
                                                           scope: kAudioObjectPropertyScopeOutput, as: UInt32(1))
        let canDefault = canDefaultValue.map { $0 != 0 } ?? true
        let hiddenValue: UInt32? = IslandCoreAudio.read(id, kAudioDevicePropertyIsHidden, as: UInt32(0))
        let hidden = hiddenValue.map { $0 != 0 } ?? false
        guard !hidden else { return nil }
        return Device(objectID: id, uid: uid, name: name, isHeadphones: headphones, priorityTier: tier,
                      canBeDefaultOutput: canDefault)
    }

    private func reloadDevice() {
        deviceListeners.removeAll()
        let device = IslandCoreAudio.defaultDevice(input: false)
        deviceID = device
        let uid = device.flatMap { IslandCoreAudio.string($0, kAudioDevicePropertyDeviceUID) }
        if currentOutputDeviceUID != uid { currentOutputDeviceUID = uid }
        if let device {
            let scope = kAudioObjectPropertyScopeOutput
            for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
                deviceListeners.add(device, selector, scope: scope) { [weak self] in self?.readLevels() }
            }
            for element: AudioObjectPropertyElement in [1, 2] {
                deviceListeners.add(device, kAudioDevicePropertyVolumeScalar, scope: scope, element: element) { [weak self] in
                    self?.readLevels()
                }
            }
        }
        readLevels()
    }

    private func readLevels() {
        guard let deviceID else {
            if systemOutputVolume != nil { systemOutputVolume = nil }
            if systemOutputMuted != nil { systemOutputMuted = nil }
            return
        }
        let volume = IslandCoreAudio.volume(deviceID, scope: kAudioObjectPropertyScopeOutput)
        let muted = IslandCoreAudio.muted(deviceID, scope: kAudioObjectPropertyScopeOutput)
        if systemOutputVolume != volume { systemOutputVolume = volume }
        if systemOutputMuted != muted { systemOutputMuted = muted }
    }

    func requestOutputAdjustment(volume: Double? = nil, muted: Bool? = nil) {
        guard let deviceID else { return }
        if let volume {
            IslandCoreAudio.setVolume(deviceID, scope: kAudioObjectPropertyScopeOutput, volume)
            // Raising the level unmutes, as the volume keys do.
            if volume > 0, systemOutputMuted == true {
                IslandCoreAudio.setMuted(deviceID, scope: kAudioObjectPropertyScopeOutput, false)
            }
        }
        if let muted { IslandCoreAudio.setMuted(deviceID, scope: kAudioObjectPropertyScopeOutput, muted) }
        readLevels()
    }

    /// Makes `uid` the output for everything, alerts included.
    @discardableResult
    func setUniversalOutputDeviceUID(_ uid: String) -> Bool {
        guard let device = outputDevices.first(where: { $0.uid == uid }) else { return false }
        let system = AudioObjectID(kAudioObjectSystemObject)
        let ok = IslandCoreAudio.write(system, kAudioHardwarePropertyDefaultOutputDevice, device.objectID)
        IslandCoreAudio.write(system, kAudioHardwarePropertyDefaultSystemOutputDevice, device.objectID)
        outputSwitchError = ok ? nil : device.name
        return ok
    }
}

// MARK: - Microphone

/// The default input's mute, as the island's microphone control switches it.
final class IslandMicrophone: ObservableObject {
    static let shared = IslandMicrophone()
    @Published private(set) var isMuted = false
    private let systemListeners = IslandAudioListeners()
    private let deviceListeners = IslandAudioListeners()
    /// The level an input without a mute switch had before it was muted.
    private var restoredVolume: Double?

    private init() {
        systemListeners.add(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice) { [weak self] in
            self?.reloadDevice()
        }
        reloadDevice()
    }

    private func reloadDevice() {
        deviceListeners.removeAll()
        if let device = IslandCoreAudio.defaultDevice(input: true) {
            for selector in [kAudioDevicePropertyMute, kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                             kAudioDevicePropertyVolumeScalar] {
                deviceListeners.add(device, selector, scope: kAudioObjectPropertyScopeInput) { [weak self] in self?.read() }
            }
        }
        read()
    }

    private func read() {
        guard let device = IslandCoreAudio.defaultDevice(input: true) else {
            if isMuted { isMuted = false }
            return
        }
        let scope = kAudioObjectPropertyScopeInput
        let muted = IslandCoreAudio.muted(device, scope: scope)
            ?? (restoredVolume != nil && (IslandCoreAudio.volume(device, scope: scope) ?? 1) == 0)
        if isMuted != muted { isMuted = muted }
    }

    func toggle() {
        guard let device = IslandCoreAudio.defaultDevice(input: true) else { return }
        let scope = kAudioObjectPropertyScopeInput
        let mute = !isMuted
        if !IslandCoreAudio.setMuted(device, scope: scope, mute) {
            // An input without a mute switch is silenced by its level.
            if mute {
                restoredVolume = IslandCoreAudio.volume(device, scope: scope) ?? 1
                IslandCoreAudio.setVolume(device, scope: scope, 0)
            } else {
                IslandCoreAudio.setVolume(device, scope: scope, restoredVolume ?? 1)
                restoredVolume = nil
            }
        }
        read()
        NotchService.shared.showMicrophone(muted: isMuted)
    }
}

// MARK: - Brightness

struct IslandBrightnessDisplay: Identifiable, Equatable {
    enum Method: Equatable { case displayServices }
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    var isActive: Bool
    var method: Method?
    var brightness: Double
}

/// Display brightness through DisplayServices, for built-in and Apple
/// displays, and the keyboard light through CoreBrightness.
final class IslandBrightness: ObservableObject {
    static let shared = IslandBrightness()

    @Published private(set) var displays: [IslandBrightnessDisplay] = []
    @Published var focusedDisplayID: CGDirectDisplayID?
    @Published private(set) var keyboardLightEnabled: Bool?
    @Published private(set) var keyboardLightLevel: Float?
    /// The island's brightness slider follows the display the keys moved.
    let islandSliderShowsFocusedDisplay = true

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias RegisterChanges = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?, CFNotificationCallback) -> Int32

    private static let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static func function<T>(_ name: String, as type: T.Type) -> T? {
        guard let displayServices, let symbol = dlsym(displayServices, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }
    private static let getBrightness = function("DisplayServicesGetBrightness", as: GetBrightness.self)
    private static let setBrightnessFunction = function("DisplayServicesSetBrightness", as: SetBrightness.self)
    private static let canChange = function("DisplayServicesCanChangeBrightness", as: CanChange.self)
    private static let registerChanges = function("DisplayServicesRegisterForBrightnessChangeNotifications",
                                                  as: RegisterChanges.self)

    private var registered = Set<CGDirectDisplayID>()
    private var ownChangeUntil: TimeInterval = 0
    private var keyboardDragging = false
    private var keyboardTimer: Timer?

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }

    static func wholePercent(_ level: Double) -> Int {
        Int((min(1, max(0, level.isFinite ? level : 0)) * 100).rounded())
    }

    /// Whether the lid is closed; nil on a Mac without one.
    static func lidClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return value as? Bool
    }

    func refresh() {
        var next: [IslandBrightnessDisplay] = []
        for screen in NSScreen.screens {
            let id = screen.notchDisplayID
            var level: Float = 0
            let readable = Self.getBrightness.map { $0(id, &level) == 0 } ?? false
            let changeable = readable && (Self.canChange?(id) ?? true)
            next.append(IslandBrightnessDisplay(id: id, name: screen.localizedName,
                                                isBuiltIn: CGDisplayIsBuiltin(id) != 0, isActive: CGDisplayIsActive(id) != 0,
                                                method: changeable ? .displayServices : nil,
                                                brightness: Double(level)))
            if changeable { registerForChanges(id) }
        }
        if next != displays { displays = next }
        if focusedDisplayID.map({ id in !displays.contains { $0.id == id } }) ?? false { focusedDisplayID = nil }
    }

    private func registerForChanges(_ id: CGDirectDisplayID) {
        guard let register = Self.registerChanges, !registered.contains(id) else { return }
        registered.insert(id)
        _ = register(id, Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer else { return }
            let owner = Unmanaged<IslandBrightness>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { owner.brightnessChanged() }
        })
    }

    /// The brightness keys, or anything else, moved a display: the island
    /// shows the new level unless the island set it itself.
    private func brightnessChanged() {
        let before = displays
        refresh()
        guard ProcessInfo.processInfo.systemUptime > ownChangeUntil,
              UserDefaults.standard.bool(forKey: IslandKey.brightnessControlEnabled) else { return }
        for display in displays {
            guard let old = before.first(where: { $0.id == display.id }),
                  abs(old.brightness - display.brightness) > 0.004 else { continue }
            focusedDisplayID = display.id
            _ = NotchService.shared.showBrightness(display.brightness)
            break
        }
    }

    func setBrightness(_ level: Double, for id: CGDirectDisplayID, announces: Bool) {
        guard let set = Self.setBrightnessFunction else { return }
        if !announces { ownChangeUntil = ProcessInfo.processInfo.systemUptime + 1 }
        _ = set(id, Float(min(1, max(0, level))))
        if let index = displays.firstIndex(where: { $0.id == id }) { displays[index].brightness = min(1, max(0, level)) }
    }

    // MARK: Keyboard light

    private static let coreBrightness: Void = {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
    }()

    private lazy var keyboardClient: NSObject? = {
        _ = Self.coreBrightness
        guard let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        return type.init()
    }()

    private var keyboardID: UInt64? {
        guard let client = keyboardClient,
              client.responds(to: NSSelectorFromString("copyKeyboardBacklightIDs")),
              let ids = client.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?
                .takeRetainedValue() as? [NSNumber] else { return nil }
        return ids.first?.uint64Value
    }

    var hasKeyboardLight: Bool { keyboardID != nil }

    func refreshKeyboardLight() {
        guard let client = keyboardClient, let id = keyboardID else {
            keyboardLightLevel = nil; keyboardLightEnabled = nil; return
        }
        let selector = NSSelectorFromString("brightnessForKeyboard:")
        guard client.responds(to: selector) else { return }
        typealias Read = @convention(c) (NSObject, Selector, UInt64) -> Float
        let read = unsafeBitCast(client.method(for: selector), to: Read.self)
        let level = read(client, selector, id)
        keyboardLightLevel = level
        keyboardLightEnabled = level > 0
        if level > 0 { UserDefaults.standard.set(Double(level), forKey: Self.lastKeyboardLevelKey) }
    }

    func setKeyboardLightLevel(_ level: Float) {
        guard let client = keyboardClient, let id = keyboardID else { return }
        let selector = NSSelectorFromString("setBrightness:forKeyboard:")
        guard client.responds(to: selector) else { return }
        typealias Write = @convention(c) (NSObject, Selector, Float, UInt64) -> Bool
        let write = unsafeBitCast(client.method(for: selector), to: Write.self)
        _ = write(client, selector, min(1, max(0, level)), id)
        keyboardLightLevel = level
        keyboardLightEnabled = level > 0
        if level > 0 { UserDefaults.standard.set(Double(level), forKey: Self.lastKeyboardLevelKey) }
    }

    func setKeyboardLightEnabled(_ enabled: Bool) {
        let last = UserDefaults.standard.object(forKey: Self.lastKeyboardLevelKey) as? Double ?? 0.5
        setKeyboardLightLevel(enabled ? Float(max(0.05, last)) : 0)
    }

    func keyboardLightDragChanged(_ dragging: Bool) {
        keyboardDragging = dragging
        if !dragging { refreshKeyboardLight() }
    }

    private static let lastKeyboardLevelKey = "islandKeyboardLightLastLevel"
}
