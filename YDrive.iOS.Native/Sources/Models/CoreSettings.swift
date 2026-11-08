import Foundation
import SwiftUI

/// Supported UI languages in YDrive iOS.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case en     = "en"
    case tr     = "tr"
    case de     = "de"
    case es     = "es"
    case ja     = "ja"
    case ar     = "ar"
    case ru     = "ru"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return LocalizationHelper.string("settings.language.system", default: "System Default")
        case .en:     return "English"
        case .tr:     return "Türkçe"
        case .de:     return "Deutsch"
        case .es:     return "Español"
        case .ja:     return "日本語"
        case .ar:     return "العربية"
        case .ru:     return "Русский"
        }
    }

    var isRTL: Bool {
        self == .ar
    }
}

/// Dynamic bundle-based localization helper honoring both iOS system/per-app settings and in-app language picker.
enum LocalizationHelper {
    static var currentLanguageCode: String {
        let stored = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        if stored != "system" {
            return stored
        }
        let preferred = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        let supported = ["en", "tr", "de", "es", "ja", "ar", "ru"]
        return supported.contains(preferred) ? preferred : "en"
    }

    static var activeBundle: Bundle {
        let code = currentLanguageCode
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return Bundle.main
    }

    static func string(_ key: String, default defaultValue: String? = nil) -> String {
        return activeBundle.localizedString(forKey: key, value: defaultValue ?? key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let formatStr = string(key)
        return String(format: formatStr, arguments: arguments)
    }
}

/// Emulation core selection supported by YDrive iOS.
enum EmulationCoreType: String, CaseIterable, Identifiable, Sendable {
    case picodrive = "picodrive"
    case ydCore    = "ydCore"

    var id: String { rawValue }

    /// User-facing title in Settings and Picker controls.
    var displayName: String {
        switch self {
        case .picodrive:
            return LocalizationHelper.string("core.picodrive.title", default: "PicoDrive (Stable)")
        case .ydCore:
            return LocalizationHelper.string("core.ydcore.title", default: "YD-Core (Experimental)")
        }
    }

    /// Short summary label for the About / Status section.
    var shortBadgeTitle: String {
        switch self {
        case .picodrive:
            return "PicoDrive"
        case .ydCore:
            return "YD-Core v1.2.0"
        }
    }
}

/// Persistent `@AppStorage` keys and snapshot model for emulation core configuration.
struct CoreSettings: Sendable {
    static let enableExperimentalKey = "enableExperimentalCore"
    static let selectedCoreKey       = "selected_emulation_core"
    static let fastMemoryKey         = "yd_fast_memory"
    static let audioInterpolationKey = "yd_audio_interpolation"
    static let forceSixButtonKey     = "yd_force_6button_pad"

    let enableExperimentalCore: Bool
    let selectedCore: EmulationCoreType
    let fastMemory: Bool
    let audioInterpolation: Bool
    let forceSixButton: Bool

    /// Reads the current persistent core settings from `UserDefaults.standard`.
    static func current() -> CoreSettings {
        let defaults = UserDefaults.standard
        let expEnabled = defaults.object(forKey: enableExperimentalKey) as? Bool ?? false
        let rawCore = defaults.string(forKey: selectedCoreKey) ?? EmulationCoreType.picodrive.rawValue
        let storedCore = EmulationCoreType(rawValue: rawCore) ?? .picodrive
        let activeCore: EmulationCoreType = expEnabled ? storedCore : .picodrive

        let fastMem = defaults.object(forKey: fastMemoryKey) as? Bool ?? true
        let audioInterp = defaults.object(forKey: audioInterpolationKey) as? Bool ?? false
        let force6Btn = defaults.object(forKey: forceSixButtonKey) as? Bool ?? false

        return CoreSettings(
            enableExperimentalCore: expEnabled,
            selectedCore: activeCore,
            fastMemory: fastMem,
            audioInterpolation: audioInterp,
            forceSixButton: force6Btn
        )
    }
}
