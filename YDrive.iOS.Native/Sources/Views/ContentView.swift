import SwiftUI

struct ContentView: View {
    var body: some View {
        // Using iOS 18/26+ Native Tab View
        TabView {
            Tab("Kütüphane", systemImage: "gamecontroller.fill") {
                GameLibraryView()
            }
            
            Tab("Ayarlar", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable) // Modern iOS/iPadOS 18+ Sidebar/Tab adaptable style
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
