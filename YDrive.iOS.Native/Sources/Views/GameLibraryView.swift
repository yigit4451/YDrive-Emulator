import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

let romUTTypes: [UTType] = [
    UTType(filenameExtension: "md"),
    UTType(filenameExtension: "bin"),
    UTType(filenameExtension: "gen"),
    UTType(filenameExtension: "smd"),
    UTType(filenameExtension: "zip"),
    UTType(filenameExtension: "chd"),
].compactMap { $0 }

struct GameLibraryView: View {
    @StateObject private var viewModel = GameLibraryViewModel()
    @State private var showingRenameAlert = false
    @State private var renameTarget: GameItem?
    @State private var renameText = ""
    @State private var showingDeleteAlert = false
    @State private var gameToDelete: GameItem?
    @State private var playingGame: GameItem?
    @State private var showingDetailsForGame: GameItem?
    @State private var showingSettings = false
    @State private var isSearchActive = false
    @FocusState private var isSearchFocused: Bool
    
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var coverTarget: GameItem?

    private let columns = [
        GridItem(.adaptive(minimum: 155, maximum: 195), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("YDrive")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.title3.weight(.medium))
                        }
                        .tint(Color.accentColor)
                    }
                    
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            viewModel.refreshMetadata()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.title3.weight(.medium))
                        }
                        .tint(Color.accentColor)

                        Button {
                            viewModel.isFilePickerPresented = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title3.weight(.bold))
                        }
                        .tint(Color.accentColor)
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
                .alert("Silmek istediğinize emin misiniz?", isPresented: $showingDeleteAlert) {
                    Button("İptal", role: .cancel) { }
                    Button("Sil", role: .destructive) {
                        if let game = gameToDelete {
                            viewModel.deleteGame(game)
                        }
                    }
                }
                .fullScreenCover(item: $playingGame) { game in
                    EmulatorView(game: game)
                }
                .sheet(item: $showingDetailsForGame) { game in
                    GameDetailView(game: game, viewModel: viewModel)
                }
                .sheet(isPresented: $showingSettings) {
                    NavigationStack {
                        SettingsView()
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button {
                                        showingSettings = false
                                    } label: {
                                        Image(systemName: "xmark")
                                            .fontWeight(.semibold)
                                    }
                                    .accessibilityLabel(NSLocalizedString("close", comment: ""))
                                    .tint(.primary)
                                }
                            }
                    }
                    .presentationDetents([.large])
                }
                .onChange(of: selectedCoverItem) { newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let game = coverTarget {
                            viewModel.updateCoverImageData(for: game, imageData: data)
                        }
                        selectedCoverItem = nil
                        coverTarget = nil
                    }
                }
                .toolbar {
                    if !isSearchActive {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Button {
                                withAnimation {
                                    isSearchActive = true
                                    isSearchFocused = true
                                }
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.blue)
                                    .font(.title3.weight(.medium))
                            }
                            Spacer()
                        }
                    } else {
                        ToolbarItemGroup(placement: .bottomBar) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                
                                TextField(NSLocalizedString("search", comment: ""), text: $viewModel.searchText)
                                    .focused($isSearchFocused)
                                    .textFieldStyle(.roundedBorder)
                                    .submitLabel(.search)
                                
                                if !viewModel.searchText.isEmpty {
                                    Button {
                                        viewModel.searchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            
                            Button(NSLocalizedString("close", comment: "")) {
                                withAnimation {
                                    isSearchActive = false
                                    isSearchFocused = false
                                }
                            }
                            .font(.body.weight(.medium))
                            .foregroundStyle(.blue)
                        }
                    }
                }
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        Group {
            if viewModel.games.isEmpty {
                emptyState
            } else if !viewModel.searchText.isEmpty && viewModel.filteredGames.isEmpty {
                noResultsState
            } else {
                ScrollView {
                    gameGrid
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
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

            Text("Genesis veya SEGA CD ROM dosyası\n(.md .bin .gen .zip .chd) ekleyin")
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

    // MARK: – No Results State
    private var noResultsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            
            Text(NSLocalizedString("no_results", comment: ""))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            
            Text(String(format: NSLocalizedString("no_results_for", comment: ""), viewModel.searchText))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .containerRelativeFrame(.vertical, alignment: .center)
    }

    // MARK: – Game Grid
    private var gameGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(viewModel.filteredGames) { game in
                Button {
                    playingGame = game
                } label: {
                    GameCardView(game: game)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        showingDetailsForGame = game
                    } label: {
                        Label("Oyun Bilgileri", systemImage: "info.circle")
                    }
                    
                    PhotosPicker(selection: $selectedCoverItem, matching: .images, photoLibrary: .shared()) {
                        Label("Kapağı Değiştir", systemImage: "photo.on.rectangle")
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        coverTarget = game
                    })
                    
                    Button {
                        renameTarget = game
                        renameText = game.title
                        showingRenameAlert = true
                    } label: {
                        Label("Yeniden Adlandır", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        gameToDelete = game
                        showingDeleteAlert = true
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
