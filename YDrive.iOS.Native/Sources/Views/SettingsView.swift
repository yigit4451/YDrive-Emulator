import SwiftUI

struct SettingsView: View {
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("showFPS") private var showFPS = false
    @AppStorage("audioEnabled") private var audioEnabled = true
    @AppStorage("frameSkip") private var frameSkip = 0

    var body: some View {
        NavigationStack {
            ZStack {
                // iOS 26 MeshGradient background
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                        [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                        [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                    ],
                    colors: [
                        Color(hex: "060A14"), .black,         Color(hex: "0D1830"),
                        .black,         Color(hex: "08101F"), .black,
                        Color(hex: "0A0E1A"), .black,         Color(hex: "050912")
                    ]
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // ── Emulator Section ──
                        settingsCard {
                            sectionHeader("Emülatör")
                            Toggle("Ses", isOn: $audioEnabled)
                                .tint(.blue)
                            Divider().background(.white.opacity(0.1))
                            Toggle("FPS Göster", isOn: $showFPS)
                                .tint(.blue)
                            Divider().background(.white.opacity(0.1))
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Frame Skip: \(frameSkip)")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Slider(value: Binding(
                                    get: { Double(frameSkip) },
                                    set: { frameSkip = Int($0) }
                                ), in: 0...5, step: 1)
                                .tint(.blue)
                            }
                        }

                        // ── Controls Section ──
                        settingsCard {
                            sectionHeader("Kontrolcü")
                            Toggle("Dokunsal Geri Bildirim", isOn: $hapticFeedback)
                                .tint(.blue)
                            Divider().background(.white.opacity(0.1))
                            HStack {
                                Text("MFi / GCController")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("Otomatik")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // ── About ──
                        settingsCard {
                            sectionHeader("Hakkında")
                            infoRow("Versiyon", "2.0.0 (Liquid Glass)")
                            Divider().background(.white.opacity(0.1))
                            infoRow("Platform", "iOS 26+, SwiftUI")
                            Divider().background(.white.opacity(0.1))
                            infoRow("Çekirdek", "libretro / PicoDrive")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(18)
        // iOS 26 glass effect
        .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.2)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
