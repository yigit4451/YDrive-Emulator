import SwiftUI

struct ContentView: View {
    var body: some View {
        // Since Tab Bar is removed, ContentView simply loads the main Game Library
        // which now handles its own native NavigationStack and Settings sheet.
        GameLibraryView()
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
