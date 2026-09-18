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

    private let columns = [
        GridItem(.adaptive(minimum: 155, maximum: 195), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.05, blue: 0.08)
                    .ignoresSafeArea()

                if viewModel.filteredGames.isEmpty {
                    emptyState
                } else {
                    gameGrid
                }
            }
            .navigationTitle("YDrive")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.searchText, prompt: "Oyun ara...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.isFilePickerPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.medium)
                    }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
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
    }

    // MARK: – Empty State
    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 72))
                .foregroundStyle(.ultraThinMaterial)
                .shadow(color: .white.opacity(0.1), radius: 10, x: 0, y: 5)
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
            .tint(Color.blue.opacity(0.8)) // Liquid glass prominent
            .padding(.top, 12)

            Spacer()
        }
        .padding(32)
    }

    // MARK: – Game Grid
    private var gameGrid: some View {
        ScrollView {
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
}

#Preview {
    GameLibraryView()
        .preferredColorScheme(.dark)
}
