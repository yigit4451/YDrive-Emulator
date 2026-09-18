import SwiftUI
import UniformTypeIdentifiers

let romUTTypes: [UTType] = [
    UTType(filenameExtension: "md"),
    UTType(filenameExtension: "bin"),
    UTType(filenameExtension: "gen"),
    UTType(filenameExtension: "smd"),
    UTType(filenameExtension: "zip"),
].compactMap { $0 }

struct GameLibraryView: View {
    @StateObject private var viewModel = GameLibraryViewModel()
    @State private var showingRenameAlert = false
    @State private var renameTarget: GameItem?
    @State private var renameText = ""
    @State private var selectedGame: GameItem?
    @State private var showingSettings = false

    private let columns = [
        GridItem(.adaptive(minimum: 155, maximum: 195), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.games.isEmpty {
                    mainContent
                } else {
                    mainContent
                        .searchable(text: $viewModel.searchText, prompt: "Ara...")
                }
            }
            .navigationTitle("YDrive")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.isFilePickerPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(Color.accentColor)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .tint(.secondary)
                }
            }
            .fileImporter(
                isPresented: $viewModel.isFilePickerPresented,
                allowedContentTypes: romUTTypes.isEmpty ? [.data] : romUTTypes,
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    urls.forEach { viewModel.addRom(url: $0) }
                }
            }
            .alert("Yeniden Adlandır", isPresented: $showingRenameAlert) {
                TextField("Yeni ad", text: $renameText)
                Button("Kaydet") {
                    if let game = renameTarget, !renameText.isEmpty {
                        viewModel.renameGame(game, to: renameText)
                    }
                }
                Button("İptal", role: .cancel) {}
            }
            .sheet(item: $selectedGame) { game in
                GameDetailView(game: game, viewModel: viewModel)
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("Ayarlar")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    showingSettings = false
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 18, weight: .semibold))
                                        .frame(width: 24, height: 24)
                                }
                                .accessibilityLabel("Kapat")
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.circle)
                                .tint(.secondary)
                            }
                        }
                }
                .presentationDetents([.large])
            }
        }
    }
    
    private var mainContent: some View {
        ScrollView {
            if viewModel.games.isEmpty {
                emptyState
            } else {
                gameGrid
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: – Empty State
    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)

            Text("Kütüphanede Oyun Yok")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            Text("Genesis / Mega Drive ROM dosyası\n(.md .bin .gen .zip) ekleyin")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                viewModel.isFilePickerPresented = true
            } label: {
                Label("ROM Ekle", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.accentColor)
            .padding(.top, 12)
        }
        .padding(32)
        .containerRelativeFrame(.vertical, alignment: .center)
    }

    // MARK: – Game Grid
    private var gameGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(viewModel.filteredGames) { game in
                Button {
                    selectedGame = game
                } label: {
                    GameCardView(game: game)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        renameTarget = game
                        renameText = game.title
                        showingRenameAlert = true
                    } label: {
                        Label("Yeniden Adlandır", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        viewModel.deleteGame(game)
                    } label: {
                        Label("Sil", systemImage: "trash")
                    }
                }
            }
        }
        .padding(16)
    }
}

#Preview {
    GameLibraryView()
        .preferredColorScheme(.dark)
}
