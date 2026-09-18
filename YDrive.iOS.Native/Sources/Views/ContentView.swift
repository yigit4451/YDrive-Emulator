import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GameLibraryView()
                .tabItem {
                    Label("Kütüphane", systemImage: "gamecontroller.fill")
                }
                .tag(0)
            
            SettingsView()
                .tabItem {
                    Label("Ayarlar", systemImage: "gearshape.fill")
                }
                .tag(1)
        }
        .tint(Color.accentColor) // Ensure selected tab uses the accent color
        // By relying strictly on SwiftUI's native TabView, we allow the OS 
        // to handle the true Liquid Glass blurring, highlighting, and refraction natively.
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
