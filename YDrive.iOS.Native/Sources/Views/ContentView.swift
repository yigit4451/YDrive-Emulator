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
        // iOS 26: glass tab bar
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
