import SwiftUI

struct SettingsView: View {
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("showFPS") private var showFPS = false
    @AppStorage("audioEnabled") private var audioEnabled = true
    @AppStorage("frameSkip") private var frameSkip = 0
    @AppStorage("controllerOpacity") private var controllerOpacity = 0.4
    @AppStorage("buttonColorsEnabled") private var buttonColorsEnabled = true
    @AppStorage("videoFilter") private var videoFilter = "Off"
    @AppStorage("m30MappingEnabled") private var m30MappingEnabled = false
    @AppStorage("allRightShoulders") private var allRightShoulders = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.05, blue: 0.08)
                    .ignoresSafeArea()
                
                Form {
                    Section(header: Text("Emülatör")) {
                        NavigationLink("BIOS Files") {
                            BiosManagerView()
                        }
                        
                        Picker("Video Filter", selection: $videoFilter) {
                            Text("Off").tag("Off")
                            Text("CRT").tag("CRT")
                            Text("Simple CRT").tag("Simple CRT")
                        }
                        
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
                        VStack(alignment: .leading) {
                            Text("Controller Opacity: \(Int(controllerOpacity * 100))%")
                            Slider(value: $controllerOpacity, in: 0.1...1.0, step: 0.05)
                                .tint(.blue)
                        }
                        
                        Toggle("Renkli Butonlar", isOn: $buttonColorsEnabled)
                            .tint(.blue)
                        
                        Toggle("Dokunsal Geri Bildirim", isOn: $hapticFeedback)
                            .tint(.blue)
                        
                        Toggle("8BitDo M30 Düzeni", isOn: $m30MappingEnabled)
                            .tint(.blue)
                        
                        Toggle("All-Right Omuz Tuşları", isOn: $allRightShoulders)
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
