// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted for Sirena from Vorssaint's IslandPowerSampler.swift: only the charge,
// charging and power-connection readings the island shows. No SMC access.

import Foundation
import IOKit

struct IslandPowerReading: Equatable {
    var chargePercent: Int?
    var isCharging = false
    var externalConnected = false
    var hasBattery = false
}

final class IslandPowerSampler {
    /// Internal-battery presence is immutable for the lifetime of a Mac boot.
    static var hasInternalBattery: Bool { batteryPresence.installed }

    /// Apple silicon desktops publish the battery service too, with
    /// BatteryInstalled false: it reports the power connection, not a battery.
    private static let batteryPresence: (service: Bool, installed: Bool) = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (false, false) }
        defer { IOObjectRelease(service) }
        let installed = IORegistryEntryCreateCFProperty(service, "BatteryInstalled" as CFString,
                                                        kCFAllocatorDefault, 0)?.takeRetainedValue()
        return (true, (installed as? Bool) != false)
    }()

    func sample() -> IslandPowerReading {
        var reading = IslandPowerReading()
        guard let props = Self.batteryProperties() else { return reading }
        reading.externalConnected = (props["ExternalConnected"] as? Bool) ?? false
        guard Self.hasInternalBattery else { return reading }
        reading.hasBattery = true
        reading.isCharging = (props["IsCharging"] as? Bool) ?? false
        if let capacity = props["CurrentCapacity"] as? Int,
           let maxCapacity = props["MaxCapacity"] as? Int, maxCapacity > 0 {
            reading.chargePercent = Int((Double(capacity) / Double(maxCapacity) * 100).rounded())
        }
        return reading
    }

    private static func batteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else {
            return nil
        }
        return properties?.takeRetainedValue() as? [String: Any]
    }
}
