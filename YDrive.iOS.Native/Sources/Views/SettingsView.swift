import SwiftUI

struct SettingsView: View {
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("showFPS") private var showFPS = false
    @AppStorage("audioEnabled") private var audioEnabled = true
    @AppStorage("frameSkip") private var frameSkip = 0

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Emülatör")) {
                    Toggle("Ses", isOn: $audioEnabled)
                        .tint(.accentColor)
                    
                    Toggle("FPS Göster", isOn: $showFPS)
                        .tint(.accentColor)
                    
                    VStack(alignment: .leading) {
                        Text("Frame Skip: \(frameSkip)")
                        Slider(value: Binding(
                            get: { Double(frameSkip) },
                            set: { frameSkip = Int($0) }
                        ), in: 0...5, step: 1)
                        .tint(.accentColor)
                    }
                }
                
                Section(header: Text("Kontrolcü")) {
                    Toggle("Dokunsal Geri Bildirim", isOn: $hapticFeedback)
                        .tint(.accentColor)
                    
                    HStack {
                        Text("MFi / GCController")
                        Spacer()
                        Text("Otomatik")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section(header: Text("Hakkında")) {
                    HStack {
                        Text("Versiyon")
                        Spacer()
                        Text("2.0.0 (Native)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Platform")
                        Spacer()
                        Text("iOS 16+, SwiftUI")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Çekirdek")
                        Spacer()
                        Text("libretro / PicoDrive")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Ayarlar")
        }
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
