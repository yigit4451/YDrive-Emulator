import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            GameLibraryView()
        }
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
