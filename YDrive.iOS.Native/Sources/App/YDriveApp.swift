import SwiftUI
import UIKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - App & Scene Delegates for Home Screen Quick Actions
// ─────────────────────────────────────────────────────────────────────────────

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let shortcutItem = options.shortcutItem {
            _ = QuickActionManager.shared.handleShortcutItem(shortcutItem)
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let handled = QuickActionManager.shared.handleShortcutItem(shortcutItem)
        completionHandler(handled)
    }
}

@main
struct YDriveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("appLanguage") private var appLanguage = "system"

    init() {
        UserDefaults.standard.register(defaults: [
            "buttonColorsEnabled": false,
            "hapticFeedback": true,
            "libraryViewMode": "grid"
        ])
    }

    private var colorScheme: ColorScheme? {
        switch appTheme {
        case "dark":  return .dark
        case "light": return .light
        default:      return nil
        }
    }

    private var locale: Locale {
        switch appLanguage {
        case "tr": return Locale(identifier: "tr")
        case "en": return Locale(identifier: "en")
        default:   return Locale.current
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(colorScheme)
                .environment(\.locale, locale)
        }
    }
}
