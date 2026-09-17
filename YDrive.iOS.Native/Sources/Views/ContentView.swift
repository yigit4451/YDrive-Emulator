import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Content Area
            Group {
                if selectedTab == 0 {
                    GameLibraryView()
                } else {
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // ── Floating Glass Dock ──
            HStack(spacing: 0) {
                dockButton(title: "Kütüphane", icon: "gamecontroller.fill", index: 0)
                dockButton(title: "Ayarlar", icon: "gearshape.fill", index: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 10)
            .padding(.horizontal, 40)
            .padding(.bottom, 24) // Floating 24pt above the bottom edge
        }
        .ignoresSafeArea(.keyboard)
    }
    
    private func dockButton(title: String, icon: String, index: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = index
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(selectedTab == index ? Color.blue : Color.white.opacity(0.6))
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
