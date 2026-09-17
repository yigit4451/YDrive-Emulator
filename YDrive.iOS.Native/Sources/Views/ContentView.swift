import SwiftUI

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
        // Use native iOS behaviors: 
        // iOS will automatically apply material to the tab bar when scrolling behind it.
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
