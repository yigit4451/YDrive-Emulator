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
        let colorScheme: ColorScheme? = {
            switch appTheme {
            case "dark": return .dark
            case "light": return .light
            default: return nil
            }
        }()
        
        ZStack {
            // Adaptive background
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            Form {
                // ── GÖRÜNÜM ───────────────────────────────────────────────────
                Section(header: Label("settings.appearance", systemImage: "paintbrush.fill")) {
                    Picker("settings.theme", selection: $appTheme) {
                        Text("settings.theme.system").tag("system")
                        Text("settings.theme.dark").tag("dark")
                        Text("settings.theme.light").tag("light")
                    }
                    .pickerStyle(.menu)

                }
                .listRowBackground(Color.clear.background(.ultraThinMaterial))

                // ── EMÜLASYON & SES ───────────────────────────────────────────
                Section(header: Label("settings.emulation", systemImage: "cpu.fill")) {
                    NavigationLink("settings.bios_files") {
                        BiosManagerView()
                    }

                    Picker("settings.video_filter", selection: $videoFilter) {
                        Text("Off").tag("Off")
                        Text("CRT").tag("CRT")
                        Text("Simple CRT").tag("Simple CRT")
                    }
                    .pickerStyle(.menu)

                    Toggle("settings.audio", isOn: $audioEnabled)
                        .tint(.blue)

                    Toggle("settings.show_fps", isOn: $showFPS)
                        .tint(.blue)
                }
                .listRowBackground(Color.clear.background(.ultraThinMaterial))

                // ── KONTROLcÜ ────────────────────────────────────────────────
                Section(header: Label("settings.controller", systemImage: "gamecontroller.fill")) {
                    // Opacity slider
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Opaklık: \(Int(controllerOpacity * 100))%")
                            .font(.subheadline)
                        Slider(value: $controllerOpacity, in: 0.1...1.0, step: 0.05)
                            .tint(.blue)
                    }

                    // Button size
                    Picker("settings.button_size", selection: $buttonSize) {
                        Text("settings.button_size.small").tag("Small")
                        Text("settings.button_size.normal").tag("Normal")
                        Text("settings.button_size.large").tag("Large")
                    }
                    .pickerStyle(.segmented)

                    // Layout
                    Picker("settings.layout", selection: $controllerLayout) {
                        Text("settings.layout.3btn").tag("3-Button")
                        Text("settings.layout.6btn").tag("6-Button")
                    }
                    .pickerStyle(.segmented)

                    Toggle("settings.colored_buttons", isOn: $buttonColorsEnabled)
                        .tint(.blue)

                    Toggle("settings.haptic", isOn: $hapticFeedback)
                        .tint(.blue)

                    Toggle("settings.m30", isOn: $m30MappingEnabled)
                        .tint(.blue)

                    Toggle("settings.shoulders", isOn: $allRightShoulders)
                        .tint(.blue)

                    HStack {
                        Text("settings.mfi")
                        Spacer()
                        Text("settings.mfi.auto")
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear.background(.ultraThinMaterial))

                // ── HAKKINDA ─────────────────────────────────────────────────
                Section(header: Label("settings.about", systemImage: "info.circle.fill")) {
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
                        Text("settings.platform")
                        Spacer()
                        Text("iOS 26+, SwiftUI")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("settings.core")
                        Spacer()
                        Text("PicoDrive / Genesis Plus GX")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    // GitHub link
                    Link(destination: URL(string: "https://github.com/yigit4451/YDrive-Emulator")!) {
                        HStack {
                            Image(systemName: "link")
                                .foregroundStyle(.blue)
                            Text("GitHub")
                                .foregroundStyle(.blue)
                        }
                    }

                    // Thanks / Licenses
                    VStack(alignment: .leading, spacing: 4) {
                        Text("settings.thanks")
                            .font(.subheadline.bold())
                        Text("settings.thanks.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear.background(.ultraThinMaterial))
            }
            .scrollContentBackground(.hidden)
        }
        .preferredColorScheme(colorScheme)
        .navigationTitle("settings")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
