import SwiftUI

// MARK: – Root: Tab-based navigation (iOS 26 TabView with glass tab bar)
struct ContentView: View {
    var body: some View {
        TabView {
            GameLibraryView()
                .tabItem {
                    Label("Kütüphane", systemImage: "gamecontroller.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("Ayarlar", systemImage: "gearshape.fill")
                }
        }
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
