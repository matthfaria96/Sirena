// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted for Sirena from Vorssaint's Permissions.swift: only what the
// Dynamic Island reads and asks for.

import AppKit
import ApplicationServices
import EventKit

final class IslandPermissions: ObservableObject {
    static let shared = IslandPermissions()

    @Published private(set) var accessibility = AXIsProcessTrusted()
    @Published private(set) var calendarAccess = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var requestingCalendar = false
    @Published private(set) var calendarRequestFailed = false
    private var calendarPermissionResolution: TimeInterval?
    private var activationObserver: NSObjectProtocol?

    /// The calendar page stays open while its permission prompt is up, and
    /// for a moment after it resolves.
    var keepsCalendarPrompt: Bool {
        NotchSupport.keepsPermissionSurface(requesting: requestingCalendar,
                                            resolvedAt: calendarPermissionResolution,
                                            now: ProcessInfo.processInfo.systemUptime)
    }

    private init() {
        // Coming back from System Settings is when a grant usually lands.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if accessibility != trusted { accessibility = trusted }
        let calendar = EKEventStore.authorizationStatus(for: .event)
        if calendarAccess != calendar { calendarAccess = calendar }
    }

    /// Reading calendar events requires full access even though the app never writes them.
    func requestCalendar() {
        guard !requestingCalendar else { return }
        requestingCalendar = true
        calendarRequestFailed = false
        let store = EKEventStore()
        store.requestFullAccessToEvents { [weak self, store] _, error in
            _ = store
            DispatchQueue.main.async {
                self?.calendarPermissionResolution = ProcessInfo.processInfo.systemUptime
                self?.requestingCalendar = false
                let status = EKEventStore.authorizationStatus(for: .event)
                self?.calendarRequestFailed = NotchCalendarSupport.requestFailed(status: status, hasError: error != nil)
                self?.calendarAccess = status
            }
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func openAccessibilitySettings() { open(pane: "Privacy_Accessibility") }
    func openCalendarSettings() { open(pane: "Privacy_Calendars") }
    func openCameraSettings() { open(pane: "Privacy_Camera") }
    func openAutomationSettings() { open(pane: "Privacy_Automation") }
    func openAudioCaptureSettings() { open(pane: "Privacy_AudioCapture") }
    func openFullDiskAccessSettings() { open(pane: "Privacy_AllFiles") }
    func openNotificationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
    }

    private func open(pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}
