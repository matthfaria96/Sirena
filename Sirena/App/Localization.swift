/// Localization.swift

import Foundation

/// Looks up a string in Sirena's own table (Sirena.xcstrings), kept apart from the
/// Localizable table inherited from Rectangle.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, table: "Sirena")
}
