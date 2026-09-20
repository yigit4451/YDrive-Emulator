import SwiftUI

struct BiosManagerView: View {
    @StateObject private var manager = BiosManager.shared
    @State private var isImporterPresented = false
    
    var body: some View {
        Form {
            Section(header: Text("SEGA CD BIOS"), footer: Text("Oyunların çalışması için doğru bölgeye ait BIOS dosyasının (.bin) yüklü olması gerekir.")) {
                biosRow(region: "USA", isInstalled: manager.isUSABiosInstalled)
                biosRow(region: "Europe", isInstalled: manager.isEuropeBiosInstalled)
                biosRow(region: "Japan", isInstalled: manager.isJapanBiosInstalled)
                
                Button {
                    isImporterPresented = true
                } label: {
                    Text("Import BIOS...")
                        .foregroundStyle(.blue)
                }
            }
            .listRowBackground(Color.clear.background(.ultraThinMaterial))
        }
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.04, green: 0.05, blue: 0.08).ignoresSafeArea())
        .navigationTitle("BIOS Files")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                _ = manager.importBios(url: url)
            case .failure(let error):
                print("Import failed: \(error.localizedDescription)")
            }
        }
    }
    
    @ViewBuilder
    private func biosRow(region: String, isInstalled: Bool) -> some View {
        HStack {
            Text(region)
            Spacer()
            if isInstalled {
                Text("Installed")
                    .foregroundStyle(.green)
            } else {
                Text("Missing")
                    .foregroundStyle(.red)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if isInstalled {
                Button(role: .destructive) {
                    manager.deleteBios(region: region)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
