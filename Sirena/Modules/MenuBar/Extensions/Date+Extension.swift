//
//  Date+Extension.swift
//  Hidden Bar
//
//  Created by Trung Phan on 22/03/2021.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import Foundation

extension Date {
    static func timeString() -> String {
        let dateFormater = DateFormatter()
        dateFormater.dateFormat = "hh:mm a"
        return dateFormater.string(from: Date())
    }
}
