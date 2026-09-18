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
            
            // ── Floating Liquid Glass Dock ──
            HStack(spacing: 0) {
                dockButton(title: "Kütüphane", icon: "gamecontroller.fill", index: 0)
                dockButton(title: "Ayarlar", icon: "gearshape.fill", index: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .applyLiquidGlassCapsule()
            .padding(.horizontal, 60)
            .padding(.bottom, 24) // Float above the bottom edge
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
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selectedTab == index ? Color.accentColor : Color.secondary)
                
                if selectedTab == index {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 4, height: 4)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
