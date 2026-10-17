// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the camera preview mirror.
struct IslandCameraPreviewFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let openButton: String
    let cameraMenuLabel: String
    let deniedMessage: String
    let noCameraMessage: String
    let permName: String
    let permExplain: String
}

extension IslandStrings {
    static func cameraPreview(_ language: IslandLanguage) -> IslandCameraPreviewFeatureStrings {
        return .enUS
    }
}

extension IslandCameraPreviewFeatureStrings {
    static let enUS = IslandCameraPreviewFeatureStrings(
        pageTitle: L("Camera preview"),
        hubDescription: L("Opens a floating mirror with your camera"),
        panelCaption: L("Check how you look before a call"),
        openButton: L("Open preview"),
        cameraMenuLabel: L("Camera"),
        deniedMessage: L("Camera access for Sirena is turned off in System Settings."),
        noCameraMessage: L("No camera detected"),
        permName: L("Camera"),
        permExplain: L("Shows your camera only in the preview window, so you can check how you look before a call. Nothing is recorded or leaves your Mac.")
    )













}
