import SwiftUI

extension NumberFormatter {
}

extension NumberFormatter {
    convenience init(
        style: NumberFormatter.Style = .none,
        minimumFractionDigits: Int? = nil,
        maximumFractionDigits: Int? = nil
    ) {
        self.init()
        numberStyle = style
        if let minDigits = minimumFractionDigits {
            self.minimumFractionDigits = minDigits
        }
        if let maxDigits = maximumFractionDigits {
            self.maximumFractionDigits = maxDigits
        }
    }
}
