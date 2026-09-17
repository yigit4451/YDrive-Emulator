import SwiftUI

// MARK: – Root: Tab-based navigation (iOS 26 TabView with glass tab bar)
struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Kütüphane", systemImage: "gamecontroller.fill") {
                GameLibraryView()
            }
            Tab("Ayarlar", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
