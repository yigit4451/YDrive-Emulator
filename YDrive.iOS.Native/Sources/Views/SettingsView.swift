import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("showFPS") private var showFPS = false
    @AppStorage("audioEnabled") private var audioEnabled = true
    @AppStorage("frameSkip") private var frameSkip = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.05), Color(white: 0.09)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {

                    // ── Header ──
                    HStack {
                        Text("Ayarlar")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)

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
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
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
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("Otomatik")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // ── About ──
                    settingsCard {
                        sectionHeader("Hakkında")
                        infoRow("Versiyon", "1.0.0")
                        Divider().background(.white.opacity(0.1))
                        infoRow("Platform", "iOS 16+, SwiftUI")
                        Divider().background(.white.opacity(0.1))
                        infoRow("Çekirdek", "libretro / PicoDrive")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.8)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
