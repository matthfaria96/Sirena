//
//  UserDefault+Extension.swift
//  Hidden Bar
//
//  Created by phucld on 12/18/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Foundation

extension UserDefaults {
    enum Key {
        static let globalKey = "hiddenBar.globalKey"
        static let numberOfSecondForAutoHide = "hiddenBar.numberOfSecondForAutoHide"
        static let isAutoHide = "hiddenBar.isAutoHide"
        static let isShowPreference = "hiddenBar.isShowPreferences"
        static let areSeparatorsHidden = "hiddenBar.areSeparatorsHidden"
        static let alwaysHiddenSectionEnabled = "hiddenBar.alwaysHiddenSectionEnabled"
        static let useFullStatusBarOnExpandEnabled = "hiddenBar.useFullStatusBarOnExpandEnabled"
        static let hoverToExpand = "hiddenBar.hoverToExpand"
        static let notchOverflowEnabled = "hiddenBar.notchOverflowEnabled"
    }
}
