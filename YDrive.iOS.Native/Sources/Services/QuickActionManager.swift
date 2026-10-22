// ─────────────────────────────────────────────────────────────────────────────
//  QuickActionManager.swift
//  YDrive iOS Native
//
//  Manages iOS Home Screen Quick Actions (3D Touch / Haptic Touch long-press)
//  allowing users to jump directly into games or add new ROMs.
// ─────────────────────────────────────────────────────────────────────────────

import UIKit
import SwiftUI

@MainActor
final class QuickActionManager: ObservableObject {
    static let shared = QuickActionManager()

    static let launchGameType = "com.yigit.ydrive.launch-game"
    static let addRomType     = "com.yigit.ydrive.add-rom"

    /// Targeted game file name/path to launch when triggered from Home screen.
    @Published var targetGameFileName: String?
    /// Set to true when user taps "Add ROM" from Home screen.
    @Published var shouldOpenAddRom = false

    private init() {}

    /// Updates dynamic shortcuts displayed on iOS Home Screen when long-pressing the app icon.
    func updateShortcuts(games: [GameItem], lastPlayedFileName: String? = nil) {
        var items: [UIApplicationShortcutItem] = []

        // 1. If there is a last played game, put it at the very top as "Continue"
        if let last = lastPlayedFileName, !last.isEmpty, let lastGame = games.first(where: { $0.fileName == last }) {
            let continueTitle = lastGame.title
            let continueSubtitle = String(format: NSLocalizedString("quick_action.continue", comment: "Continue: %@"), lastGame.consoleName)
            let item = UIApplicationShortcutItem(
                type: Self.launchGameType,
                localizedTitle: continueTitle,
                localizedSubtitle: continueSubtitle,
                icon: UIApplicationShortcutIcon(systemImageName: "play.circle.fill"),
                userInfo: ["fileName": lastGame.fileName as NSString]
            )
            items.append(item)
        }

        // 2. Add other games up to 3 game shortcuts total
        for game in games {
            if items.count >= 3 { break }
            let alreadyAdded = items.contains { ($0.userInfo?["fileName"] as? String) == game.fileName }
            if alreadyAdded { continue }

            let item = UIApplicationShortcutItem(
                type: Self.launchGameType,
                localizedTitle: game.title,
                localizedSubtitle: game.consoleName,
                icon: UIApplicationShortcutIcon(systemImageName: "gamecontroller.fill"),
                userInfo: ["fileName": game.fileName as NSString]
            )
            items.append(item)
        }

        // 3. Add ROM shortcut
        let addRomTitle = NSLocalizedString("quick_action.add_rom", comment: "Add ROM")
        let addRomItem = UIApplicationShortcutItem(
            type: Self.addRomType,
            localizedTitle: addRomTitle,
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "plus.circle"),
            userInfo: nil
        )
        items.append(addRomItem)

        UIApplication.shared.shortcutItems = items
    }

    /// Handles a shortcut item received upon app launch or while running in the background.
    func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        if shortcutItem.type == Self.launchGameType {
            if let fileName = shortcutItem.userInfo?["fileName"] as? String {
                self.targetGameFileName = fileName
                return true
            }
        } else if shortcutItem.type == Self.addRomType {
            self.shouldOpenAddRom = true
            return true
        }
        return false
    }
}
