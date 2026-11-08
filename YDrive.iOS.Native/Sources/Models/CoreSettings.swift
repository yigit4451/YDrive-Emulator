import Foundation
import SwiftUI

/// Emulation core selection supported by YDrive iOS.
enum EmulationCoreType: String, CaseIterable, Identifiable, Sendable {
    case picodrive = "picodrive"
    case ydCore    = "ydCore"

    var id: String { rawValue }

    /// User-facing title in Settings and Picker controls.
    var displayName: String {
        switch self {
        case .picodrive:
            return NSLocalizedString("PicoDrive (Varsayılan / Kararlı)", comment: "Default stable PicoDrive core")
        case .ydCore:
            return NSLocalizedString("YD-Core v1.2.0 (Deneysel / Yerel Motor)", comment: "Experimental native YD-Core v1.2.0")
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
