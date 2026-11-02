/// ConnectedDevices.swift
///
/// The Bluetooth accessories connected right now, for Sirena's menu: each one's name, kind and
/// battery, as squares side by side. Read only while the menu is open.

import AppKit
import CoreBluetooth
import Foundation
import IOBluetooth
import SwiftUI

struct ConnectedDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let minorType: String
    /// Lowest of the device's batteries, so AirPods show the emptier bud.
    let battery: Int?

    /// The kind in words, under the name.
    var kindLabel: String {
        switch minorType.lowercased() {
        case "headphones", "headset": return L("Headphones")
        case "keyboard": return L("Keyboard")
        case "mouse": return L("Mouse")
        case "trackpad": return L("Trackpad")
        case "gamepad": return L("Game controller")
        case "speaker": return L("Speaker")
        default: return "Bluetooth"
        }
    }

    func withBattery(_ level: Int?) -> ConnectedDevice {
        ConnectedDevice(id: id, name: name, minorType: minorType, battery: level)
    }

    var symbol: String {
        switch minorType.lowercased() {
        case "gamepad": return "gamecontroller"
        case "speaker": return "hifispeaker"
        case "phone": return "iphone"
        default:
            let kind = IslandPeripheralBatterySupport.kind(product: name, minorType: minorType, primaryUsagePage: nil,
                                                           primaryUsage: nil, usagePairs: [])
            return NotchAccessorySupport.symbol(for: kind, name: name)
        }
    }
}

enum ConnectedDeviceReader {
    /// Connected devices, from System Information, which needs no permission.
    static func connected() -> [ConnectedDevice] {
        let result = IslandBoundedProcessRunner.run(
            "/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json", "-detailLevel", "basic"],
            timeout: 5, maxOutputBytes: 4 * 1024 * 1024, cancellation: IslandBoundedProcessCancellation())
        let devices = IslandPeripheralBatterySupport.connectedBluetoothEntries(from: result.output).map { name, properties in
            ConnectedDevice(id: IslandPeripheralBatterySupport.string(from: properties["device_address"]) ?? name,
                            name: name,
                            minorType: IslandPeripheralBatterySupport.string(from: properties["device_minorType"]) ?? "",
                            battery: IslandPeripheralBatterySupport.bluetoothPercent(in: properties))
        }
        return devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// System Information's batteries often have gaps: classic devices fill them from
    /// IOBluetooth, Bluetooth LE ones (keyboards, mice) from their Battery Service. Both need
    /// Bluetooth permission and would make macOS ask for it, so they wait until it's allowed
    /// in Geral.
    static func fillingBatteries(of devices: [ConnectedDevice]) async -> [ConnectedDevice] {
        guard devices.contains(where: { $0.battery == nil }),
              CBManager.authorization == .allowedAlways else { return devices }
        var found = classicLevels()
        if devices.contains(where: { $0.battery == nil && found[$0.name] == nil }) {
            found.merge(await lowEnergyLevels()) { current, _ in current }
        }
        return devices.map { device in
            guard device.battery == nil, let level = found[device.name] else { return device }
            return device.withBattery(level)
        }
    }

    /// The last level classic devices (headphones, speakers) reported, as IOBluetooth keeps it.
    private static func classicLevels() -> [String: Int] {
        let keys = ["batteryPercentSingle", "batteryPercentCombined", "batteryPercentLeft", "batteryPercentRight"]
        var result: [String: Int] = [:]
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] where device.isConnected() {
            let levels = keys.compactMap { key -> Int? in
                guard device.responds(to: NSSelectorFromString(key)),
                      let level = (device.value(forKey: key) as? NSNumber)?.intValue,
                      (1...100).contains(level) else { return nil }
                return level
            }
            if let name = device.name, let lowest = levels.min() { result[name] = lowest }
        }
        return result
    }

    /// The island's Battery Service read; it always finishes, within five seconds.
    private static func lowEnergyLevels() async -> [String: Int] {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "sirena.connected-devices.battery", qos: .utility)
            queue.async {
                var reader: IslandPeripheralBluetoothReading?
                reader = BluetoothBatteryRead(queue: queue, cancellation: IslandBoundedProcessCancellation()) { readings in
                    continuation.resume(returning: Dictionary(readings.map { ($0.name, $0.percent) }) { first, _ in first })
                    reader = nil
                }
                reader?.start()
            }
        }
    }
}

@MainActor
@Observable
final class ConnectedDevicesModel {
    static let shared = ConnectedDevicesModel()

    private(set) var devices: [ConnectedDevice] = []
    private(set) var hasRead = false
    private var lastRead: Date?
    private var isReading = false

    private init() {}

    /// System Information takes a moment, so a menu reopened right away keeps the last reading.
    func refresh(olderThan age: TimeInterval) async {
        if Showcase.isActive {
            devices = Self.showcaseDevices
            hasRead = true
            return
        }
        guard !isReading, lastRead.map({ Date().timeIntervalSince($0) >= age }) ?? true else { return }
        isReading = true
        let listed = await Task.detached(priority: .utility) { ConnectedDeviceReader.connected() }.value
        // The list shows at once, with the batteries known so far; the rest may take a while.
        let known = Dictionary(devices.map { ($0.id, $0.battery) }) { first, _ in first }
        devices = listed.map { $0.battery == nil ? $0.withBattery(known[$0.id] ?? nil) : $0 }
        hasRead = true
        let filled = await Task.detached(priority: .utility) { await ConnectedDeviceReader.fillingBatteries(of: listed) }.value
        devices = filled
        lastRead = Date()
        isReading = false
    }

    private static let showcaseDevices = [
        ConnectedDevice(id: "1", name: "AirPods Pro", minorType: "Headphones", battery: 82),
        ConnectedDevice(id: "2", name: "Magic Keyboard", minorType: "Keyboard", battery: 64),
        ConnectedDevice(id: "3", name: "Magic Mouse", minorType: "Mouse", battery: 17),
    ]
}

// MARK: - In the menu

struct ConnectedDevicesSection: View {
    private static let columns = 3

    @State private var model = ConnectedDevicesModel.shared
    @State private var showsAll = false

    var body: some View {
        let devices = model.devices
        let folds = devices.count > Self.columns
        let shown = folds && !showsAll ? Array(devices.prefix(Self.columns)) : devices
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(L("Connected Devices"))
                    .font(.callout.weight(.medium))
                if !devices.isEmpty {
                    Text(verbatim: "\(devices.count)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer(minLength: 4)
                if folds {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { showsAll.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showsAll ? L("Show fewer") : L("Show all"))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .rotationEffect(.degrees(showsAll ? 180 : 0))
                        }
                        .font(.caption.weight(.medium))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Open Bluetooth settings"))
                .accessibilityLabel(L("Open Bluetooth settings"))
            }
            if devices.isEmpty {
                Text(model.hasRead ? L("No Bluetooth devices connected") : L("Looking for devices…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: Self.columns), spacing: 6) {
                    ForEach(shown) { ConnectedDeviceTile(device: $0) }
                }
            }
        }
        // Lives as long as the menu is open: a device that just connected shows up on its own.
        .task {
            await model.refresh(olderThan: 15)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await model.refresh(olderThan: 30)
            }
        }
    }
}

/// One accessory: its symbol, battery, name and kind, with the charge as a thin bar.
private struct ConnectedDeviceTile: View {
    let device: ConnectedDevice
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Image(systemName: device.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(height: 18)
                Spacer(minLength: 2)
                if let level = device.battery {
                    Text(verbatim: "\(level)%")
                        .font(.system(size: 11.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(level <= 20 ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: device.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(verbatim: device.kindLabel)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Capsule()
                .fill(device.battery == nil ? AnyShapeStyle(.clear) : AnyShapeStyle(.quaternary))
                .frame(height: 3)
                .overlay(alignment: .leading) {
                    if let level = device.battery {
                        GeometryReader { geometry in
                            Capsule()
                                .fill(level <= 20 ? Color.red : Color.green)
                                .frame(width: max(2, geometry.size.width * CGFloat(min(level, 100)) / 100))
                        }
                    }
                }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 84, maxHeight: 84, alignment: .topLeading)
        .background(isHovering ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary.opacity(0.5)),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in withAnimation(.snappy(duration: 0.15)) { isHovering = hovering } }
        .help(device.battery != nil ? device.name
              : CBManager.authorization == .allowedAlways ? L("\(device.name) doesn't report its battery")
              : L("Allow Bluetooth in General to see the battery"))
    }
}
