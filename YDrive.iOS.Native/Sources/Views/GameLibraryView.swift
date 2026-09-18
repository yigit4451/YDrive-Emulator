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
        ZStack(alignment: .top) {
            // ── Background Content Area ──
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Safe area padding for the floating header
                    Color.clear.frame(height: 70)
                    
                    if viewModel.filteredGames.isEmpty {
                        emptyState
                    } else {
                        gameGrid
                    }
                    
                    // Safe area padding for the floating bottom dock
                    Color.clear.frame(height: 100)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            
            // ── Floating Glass Header ──
            floatingHeader
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
    
    // MARK: – Floating Header
    private var floatingHeader: some View {
        HStack(spacing: 12) {
            Text("YDrive")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            
            Spacer()
            
            // Search Bar Component
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Ara...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
            .clipShape(Capsule())
            
            Button {
                viewModel.isFilePickerPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.accentColor)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .applyLiquidGlassCapsule()
        .padding(.horizontal, 16)
        .padding(.top, 8) // Float slightly below the top safe area
    }

    // MARK: – Empty State
    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 100)

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
