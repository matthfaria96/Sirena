// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchFilesStrings {
    let archive: String
    let archiveHint: String
    let saved: String
    let downloadsTitle: String
    let downloadsDescription: String
    let downloadsHint: String
    let chooseFolder: String
    let folderUnavailable: String
    let waiting: String
    let inProgress: String
    let totalUnknown: String
    let completed: String
    let clearFolder: String
    let optimizeMedia: String
    let optimizeDropHint: String
    let resumeMedia: String
}

extension IslandStrings {
    static func notchFiles(_ language: IslandLanguage) -> NotchFilesStrings {
        return NotchFilesStrings(
            archive: L("Create ZIP"),
            archiveHint: L("Each selected item is saved as a separate ZIP. Originals stay unchanged."),
            saved: L("Saved"),
            downloadsTitle: L("Downloads"),
            downloadsDescription: L("See files arriving in a folder you choose, directly in the Dynamic Island."),
            downloadsHint: L("Choose the folder where your browser saves downloads. Only that folder is watched."),
            chooseFolder: L("Choose Folder…"),
            folderUnavailable: L("This folder is unavailable. Choose it again to restore access."),
            waiting: L("No files in this folder"),
            inProgress: L("Downloading"),
            totalUnknown: L("Total size unavailable"),
            completed: L("Download complete"),
            clearFolder: L("Forget Folder"),
            optimizeMedia: L("Optimize media"),
            optimizeDropHint: L("Drag images or one video onto the island, then drop on Optimize media to choose how to save a copy."),
            resumeMedia: L("Return to media"))
    }
}
