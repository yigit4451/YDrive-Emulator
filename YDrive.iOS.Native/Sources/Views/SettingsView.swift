import SwiftUI

struct SettingsView: View {
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("showFPS") private var showFPS = false
    @AppStorage("audioEnabled") private var audioEnabled = true
    @AppStorage("frameSkip") private var frameSkip = 0

    var body: some View {
        NavigationStack {
            ZStack {
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                        [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                        [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                    ],
                    colors: [
                        Color(red: 0.0, green: 0.0, blue: 0.0), Color(red: 0.05, green: 0.1, blue: 0.2), Color(red: 0.0, green: 0.0, blue: 0.0),
                        Color(red: 0.02, green: 0.05, blue: 0.1), Color(red: 0.1, green: 0.2, blue: 0.4), Color(red: 0.02, green: 0.05, blue: 0.1),
                        Color(red: 0.0, green: 0.0, blue: 0.0), Color(red: 0.05, green: 0.1, blue: 0.2), Color(red: 0.0, green: 0.0, blue: 0.0)
                    ]
                )
                .ignoresSafeArea()
                
                Form {
                    Section(header: Text("Emülatör")) {
                        Toggle("Ses", isOn: $audioEnabled)
                            .tint(.blue)
                        
                        Toggle("FPS Göster", isOn: $showFPS)
                            .tint(.blue)
                        
                        VStack(alignment: .leading) {
                            Text("Frame Skip: \(frameSkip)")
                            Slider(value: Binding(
                                get: { Double(frameSkip) },
                                set: { frameSkip = Int($0) }
                            ), in: 0...5, step: 1)
                            .tint(.blue)
                        }
                    }
                    .listRowBackground(Color.clear.background(.ultraThinMaterial))
                    
                    Section(header: Text("Kontrolcü")) {
                        Toggle("Dokunsal Geri Bildirim", isOn: $hapticFeedback)
                            .tint(.blue)
                        
                        HStack {
                            Text("MFi / GCController")
                            Spacer()
                            Text("Otomatik")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear.background(.ultraThinMaterial))
                    
                    Section(header: Text("Hakkında")) {
                        HStack {
                            Text("Versiyon")
                            Spacer()
                            Text("2.0.0 (Native Liquid Glass)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Platform")
                            Spacer()
                            Text("iOS 26+, SwiftUI")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Çekirdek")
                            Spacer()
                            Text("libretro / PicoDrive")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear.background(.ultraThinMaterial))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Ayarlar")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
