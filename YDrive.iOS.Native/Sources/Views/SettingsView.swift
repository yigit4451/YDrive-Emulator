import SwiftUI

struct SettingsView: View {
    // Appearance
    @AppStorage("appTheme")            private var appTheme          = "system"
    @AppStorage("appLanguage")         private var appLanguage        = "system"

    // Emulation & Audio
    @AppStorage("audioEnabled")        private var audioEnabled        = true
    @AppStorage("showFPS")             private var showFPS             = false
    @AppStorage("videoFilter")         private var videoFilter         = "Off"

    // Controller
    @AppStorage("hapticFeedback")      private var hapticFeedback      = true
    @AppStorage("controllerOpacity")   private var controllerOpacity   = 0.4
    @AppStorage("buttonColorsEnabled") private var buttonColorsEnabled = true
    @AppStorage("controllerLayout")    private var controllerLayout    = "3-Button"
    @AppStorage("buttonSize")          private var buttonSize          = "Normal"
    @AppStorage("m30MappingEnabled")   private var m30MappingEnabled   = false
    @AppStorage("allRightShoulders")   private var allRightShoulders   = false

    var body: some View {
        ZStack {
            // Adaptive background
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            Form {
                // ── GÖRÜNÜM ───────────────────────────────────────────────────
                Section(header: Label(NSLocalizedString("settings.appearance", comment: ""), systemImage: "paintbrush.fill")) {
                    Picker(NSLocalizedString("settings.theme", comment: ""), selection: $appTheme) {
                        Text(NSLocalizedString("settings.theme.system", comment: "")).tag("system")
                        Text(NSLocalizedString("settings.theme.dark",   comment: "")).tag("dark")
                        Text(NSLocalizedString("settings.theme.light",  comment: "")).tag("light")
                    }
                    .pickerStyle(.menu)

                    Picker(NSLocalizedString("settings.language", comment: ""), selection: $appLanguage) {
                        Text(NSLocalizedString("settings.language.system", comment: "")).tag("system")
                        Text(NSLocalizedString("settings.language.tr",     comment: "")).tag("tr")
                        Text(NSLocalizedString("settings.language.en",     comment: "")).tag("en")
                    }
                    .pickerStyle(.menu)
                }
                .listRowBackground(Color.clear.background(.ultraThinMaterial))

                // ── EMÜLASYON & SES ───────────────────────────────────────────
                Section(header: Label(NSLocalizedString("settings.emulation", comment: ""), systemImage: "cpu.fill")) {
                    NavigationLink(NSLocalizedString("settings.bios_files", comment: "")) {
                        BiosManagerView()
                    }

                    Picker(NSLocalizedString("settings.video_filter", comment: ""), selection: $videoFilter) {
                        Text("Off").tag("Off")
                        Text("CRT").tag("CRT")
                        Text("Simple CRT").tag("Simple CRT")
                    }
                    .pickerStyle(.menu)

                    Toggle(NSLocalizedString("settings.audio", comment: ""), isOn: $audioEnabled)
                        .tint(.blue)

                    Toggle(NSLocalizedString("settings.show_fps", comment: ""), isOn: $showFPS)
                        .tint(.blue)
                }
                .listRowBackground(Color.clear.background(.ultraThinMaterial))

                // ── KONTROLcÜ ────────────────────────────────────────────────
                Section(header: Label(NSLocalizedString("settings.controller", comment: ""), systemImage: "gamecontroller.fill")) {
                    // Opacity slider
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: NSLocalizedString("settings.opacity", comment: ""), Int(controllerOpacity * 100)))
                            .font(.subheadline)
                        Slider(value: $controllerOpacity, in: 0.1...1.0, step: 0.05)
                            .tint(.blue)
                    }

                    // Button size
                    Picker(NSLocalizedString("settings.button_size", comment: ""), selection: $buttonSize) {
                        Text(NSLocalizedString("settings.button_size.small",  comment: "")).tag("Small")
                        Text(NSLocalizedString("settings.button_size.normal", comment: "")).tag("Normal")
                        Text(NSLocalizedString("settings.button_size.large",  comment: "")).tag("Large")
                    }
                    .pickerStyle(.segmented)

                    // Layout
                    Picker(NSLocalizedString("settings.layout", comment: ""), selection: $controllerLayout) {
                        Text(NSLocalizedString("settings.layout.3btn", comment: "")).tag("3-Button")
                        Text(NSLocalizedString("settings.layout.6btn", comment: "")).tag("6-Button")
                    }
                    .pickerStyle(.segmented)

                    Toggle(NSLocalizedString("settings.colored_buttons", comment: ""), isOn: $buttonColorsEnabled)
                        .tint(.blue)

                    Toggle(NSLocalizedString("settings.haptic", comment: ""), isOn: $hapticFeedback)
                        .tint(.blue)

                    Toggle(NSLocalizedString("settings.m30", comment: ""), isOn: $m30MappingEnabled)
                        .tint(.blue)

                    Toggle(NSLocalizedString("settings.shoulders", comment: ""), isOn: $allRightShoulders)
                        .tint(.blue)

                    HStack {
                        Text(NSLocalizedString("settings.mfi", comment: ""))
                        Spacer()
                        Text(NSLocalizedString("settings.mfi.auto", comment: ""))
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear.background(.ultraThinMaterial))

                // ── HAKKINDA ─────────────────────────────────────────────────
                Section(header: Label(NSLocalizedString("settings.about", comment: ""), systemImage: "info.circle.fill")) {
                    // Logo + version badge
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [Color(red: 0.04, green: 0.34, blue: 0.85),
                                             Color(red: 0.53, green: 0.06, blue: 0.93)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 54, height: 54)
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("YDrive")
                                .font(.headline.bold())
                            Text("v2.0.0 Native Liquid Glass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)

                    HStack {
                        Text(NSLocalizedString("settings.platform", comment: ""))
                        Spacer()
                        Text("iOS 26+, SwiftUI")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text(NSLocalizedString("settings.core", comment: ""))
                        Spacer()
                        Text(NSLocalizedString("settings.core.value", comment: ""))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    // GitHub link
                    Link(destination: URL(string: NSLocalizedString("settings.github.url", comment: ""))!) {
                        HStack {
                            Image(systemName: "link")
                                .foregroundStyle(.blue)
                            Text(NSLocalizedString("settings.github", comment: ""))
                                .foregroundStyle(.blue)
                        }
                    }

                    // Thanks / Licenses
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("settings.thanks", comment: ""))
                            .font(.subheadline.bold())
                        Text(NSLocalizedString("settings.thanks.text", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear.background(.ultraThinMaterial))
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(NSLocalizedString("settings", comment: ""))
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
