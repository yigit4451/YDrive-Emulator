import SwiftUI

struct BiosManagerView: View {
    @StateObject private var manager = BiosManager.shared
    @State private var isImporterPresented = false
    @State private var regionToDelete: String?
    @State private var showingDeleteAlert = false
    
    var body: some View {
        Form {
            Section(header: Text("SEGA CD BIOS"), footer: Text("Oyunların çalışması için doğru bölgeye ait BIOS dosyasının (.bin) yüklü olması gerekir.")) {
                biosRow(region: "USA", isInstalled: manager.isUSABiosInstalled)
                biosRow(region: "Europe", isInstalled: manager.isEuropeBiosInstalled)
                biosRow(region: "Japan", isInstalled: manager.isJapanBiosInstalled)
                
                if !manager.isUSABiosInstalled || !manager.isEuropeBiosInstalled || !manager.isJapanBiosInstalled {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Text("Import BIOS...")
                            .foregroundStyle(.blue)
                    }
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
        .alert("Silmek istediğinize emin misiniz?", isPresented: $showingDeleteAlert) {
            Button("İptal", role: .cancel) { }
            Button("Sil", role: .destructive) {
                if let region = regionToDelete {
                    manager.deleteBios(region: region)
                }
            }
        }
    }
    
    @ViewBuilder
    private func biosRow(region: String, isInstalled: Bool) -> some View {
        HStack {
            Text(region)
            Spacer()
            if isInstalled {
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
                
                Button {
                    regionToDelete = region
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .padding(.leading, 8)
            } else {
                Image(systemName: "xmark")
                    .foregroundStyle(.red)
            }
        }
    }
}
