import SwiftUI

@main
struct YDriveApp: App {
    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("appLanguage") private var appLanguage = "system"

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
