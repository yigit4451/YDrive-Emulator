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
    UTType(filenameExtension: "32x"),
    UTType(filenameExtension: "sms"),
    UTType(filenameExtension: "gg"),
    UTType(filenameExtension: "iso"),
    UTType(filenameExtension: "cue"),
].compactMap { $0 }

struct GameLibraryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = GameLibraryViewModel()
    @ObservedObject private var quickActionManager = QuickActionManager.shared

    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("libraryViewMode") private var viewMode = "grid" // "grid" or "list"
    @AppStorage("lastPlayedFileName") private var lastPlayedFileName = ""

    @State private var showingRenameAlert = false
    @State private var renameTarget: GameItem?
    @State private var renameText = ""
    @State private var showingDeleteAlert = false
    @State private var gameToDelete: GameItem?
    @State private var playingGame: GameItem?
    @State private var showingDetailsForGame: GameItem?
    @State private var showingSettings = false
    
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var coverTarget: GameItem?
    @State private var showingCoverPicker = false

    private var colorScheme: ColorScheme? {
        switch appTheme {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 155, maximum: 195), spacing: 16)
    ]

    /// Red gallery icon with an xmark at its bottom-right corner, used for "Remove Artwork" in the card menu.
    private static let removeArtworkIcon: UIImage = {
        let photoCfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let xCfg = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        let photo = UIImage(systemName: "photo.on.rectangle", withConfiguration: photoCfg)?
            .withTintColor(.systemRed, renderingMode: .alwaysOriginal)
        let xmark = UIImage(systemName: "xmark", withConfiguration: xCfg)?
            .withTintColor(.systemRed, renderingMode: .alwaysOriginal)
        guard let photo, let xmark else { return UIImage() }
        let canvasWidth = photo.size.width + 4
        let canvasHeight = photo.size.height + 4
        let size = CGSize(width: canvasWidth, height: canvasHeight)
        let img = UIGraphicsImageRenderer(size: size).image { _ in
            photo.draw(at: CGPoint(x: 0, y: 0))
            let xPos = canvasWidth - xmark.size.width
            let yPos = canvasHeight - xmark.size.height
            xmark.draw(at: CGPoint(x: xPos, y: yPos))
        }
        return img.withRenderingMode(.alwaysOriginal)
    }()

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("YDrive")
                .searchable(
                    text: $viewModel.searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(NSLocalizedString("search", comment: ""))
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.title3.weight(.medium))
                        }
                        .tint(Color.accentColor)
                        .accessibilityLabel(NSLocalizedString("settings", comment: ""))
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewMode = (viewMode == "grid") ? "list" : "grid"
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: viewMode == "grid" ? "list.bullet" : "square.grid.2x2")
                                .font(.title3.weight(.medium))
                        }
                        .tint(Color.accentColor)
                        .accessibilityLabel(viewMode == "grid" ? Text(NSLocalizedString("library.list_view", comment: "")) : Text(NSLocalizedString("library.grid_view", comment: "")))
                    }

                    ToolbarSpacer(.fixed, placement: .topBarTrailing)

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.isFilePickerPresented = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title3.weight(.bold))
                        }
                        .tint(Color.accentColor)
                        .accessibilityLabel(Text(NSLocalizedString("library.add_rom", comment: "")))
                    }
                }
            .fileImporter(
                    isPresented: $viewModel.isFilePickerPresented,
                    allowedContentTypes: romUTTypes.isEmpty ? [.data] : romUTTypes,
                    allowsMultipleSelection: true
                ) { result in
                    if case .success(let urls) = result {
                        urls.forEach { viewModel.addRom(url: $0) }
                        quickActionManager.updateShortcuts(games: viewModel.games, lastPlayedFileName: lastPlayedFileName)
                    }
                }
                .alert("Rename", isPresented: $showingRenameAlert) {
                    TextField("New name", text: $renameText)
                    Button("Save") {
                        if let game = renameTarget, !renameText.isEmpty {
                            viewModel.renameGame(game, to: renameText)
                            quickActionManager.updateShortcuts(games: viewModel.games, lastPlayedFileName: lastPlayedFileName)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .alert("Are you sure you want to delete?", isPresented: $showingDeleteAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        if let game = gameToDelete {
                            viewModel.deleteGame(game)
                            quickActionManager.updateShortcuts(games: viewModel.games, lastPlayedFileName: lastPlayedFileName)
                        }
                    }
                }
                .fullScreenCover(item: $playingGame) { game in
                    EmulatorView(game: game, viewModel: viewModel)
                        .defersSystemGestures(on: .all)
                        .preferredColorScheme(colorScheme)
                }
                .sheet(item: $showingDetailsForGame) { game in
                    GameDetailView(initialGame: game, viewModel: viewModel)
                        .preferredColorScheme(colorScheme)
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
                    .preferredColorScheme(colorScheme)
                }
                .photosPicker(isPresented: $showingCoverPicker, selection: $selectedCoverItem, matching: .images, photoLibrary: .shared())
                .onChange(of: selectedCoverItem) { _, newItem in
                    guard let newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let game = coverTarget {
                            viewModel.updateCoverImageData(for: game, imageData: data)
                        }
                        selectedCoverItem = nil
                        coverTarget = nil
                    }
                }
                .onChange(of: quickActionManager.targetGameFileName) { _, fileName in
                    guard let fileName, !fileName.isEmpty else { return }
                    if let game = viewModel.games.first(where: { $0.fileName == fileName }) {
                        playingGame = game
                        lastPlayedFileName = game.fileName
                    }
                    quickActionManager.targetGameFileName = nil
                }
                .onChange(of: quickActionManager.shouldOpenAddRom) { _, shouldOpen in
                    if shouldOpen {
                        viewModel.isFilePickerPresented = true
                        quickActionManager.shouldOpenAddRom = false
                    }
                }
                .onChange(of: playingGame) { _, newGame in
                    if let newGame {
                        lastPlayedFileName = newGame.fileName
                        quickActionManager.updateShortcuts(games: viewModel.games, lastPlayedFileName: newGame.fileName)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        viewModel.syncWithDocumentsDirectory()
                        quickActionManager.updateShortcuts(games: viewModel.games, lastPlayedFileName: lastPlayedFileName)
                    }
                }
                .onAppear {
                    viewModel.syncWithDocumentsDirectory()
                    quickActionManager.updateShortcuts(games: viewModel.games, lastPlayedFileName: lastPlayedFileName)
                    // Check if a shortcut was queued before view mounted
                    if let target = quickActionManager.targetGameFileName,
                       let game = viewModel.games.first(where: { $0.fileName == target }) {
                        playingGame = game
                        lastPlayedFileName = game.fileName
                        quickActionManager.targetGameFileName = nil
                    } else if quickActionManager.shouldOpenAddRom {
                        viewModel.isFilePickerPresented = true
                        quickActionManager.shouldOpenAddRom = false
                    }
                }
        }
        .preferredColorScheme(colorScheme)
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
                    if viewMode == "grid" {
                        gameGrid
                    } else {
                        gameList
                    }
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

            Text("No Games in Library")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            Text(NSLocalizedString("library.empty.subtitle", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                viewModel.isFilePickerPresented = true
            } label: {
                Label("Add ROM", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.glassProminent)
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
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contextMenu {
                    contextMenuContent(for: game)
                }
            }
        }
        .padding(16)
    }

    // MARK: – Game List
    private var gameList: some View {
        LazyVStack(spacing: 10) {
            ForEach(viewModel.filteredGames) { game in
                Button {
                    playingGame = game
                } label: {
                    gameRow(for: game)
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contextMenu {
                    contextMenuContent(for: game)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func gameRow(for game: GameItem) -> some View {
        HStack(spacing: 14) {
            // Artwork / Cover thumbnail
            ZStack {
                if let uiImage = game.resolveCoverImage() {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipped()
                } else {
                    Color(UIColor.secondarySystemFill)
                    Image(systemName: "gamecontroller.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(game.consoleName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(consoleColor(for: game.consoleName))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(consoleColor(for: game.consoleName).opacity(0.15))
                        .clipShape(Capsule())

                    if let year = game.releaseYear {
                        Text(year)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
    }

    private func consoleColor(for name: String) -> Color {
        switch name {
        case "SEGA 32X":
            return Color(red: 255/255, green: 80/255, blue: 50/255)
        case "SEGA Master System":
            return Color(red: 170/255, green: 70/255, blue: 230/255)
        case "SEGA CD":
            return Color(red: 0/255, green: 200/255, blue: 215/255)
        case "SEGA Game Gear":
            return Color(red: 60/255, green: 200/255, blue: 120/255)
        default:
            return Color.blue
        }
    }

    // MARK: – Context Menu Content
    @ViewBuilder
    private func contextMenuContent(for game: GameItem) -> some View {
        Button {
            playingGame = game
        } label: {
            Label(NSLocalizedString("play", comment: ""), systemImage: "play.fill")
        }

        Button {
            showingDetailsForGame = game
        } label: {
            Label(NSLocalizedString("library.game_info", comment: ""), systemImage: "info.circle")
        }
        
        Button {
            coverTarget = game
            showingCoverPicker = true
        } label: {
            Label(NSLocalizedString("change_cover", comment: ""), systemImage: "photo.on.rectangle")
        }

        Button {
            renameTarget = game
            renameText = game.title
            showingRenameAlert = true
        } label: {
            Label(NSLocalizedString("library.rename", comment: ""), systemImage: "pencil")
        }

        if game.coverImagePath != nil || game.resolveCoverImage() != nil {
            Button(role: .destructive) {
                viewModel.removeCoverImage(for: game)
            } label: {
                Label {
                    Text(NSLocalizedString("remove_artwork", comment: ""))
                } icon: {
                    Image(uiImage: Self.removeArtworkIcon)
                }
            }
        }

        Button(role: .destructive) {
            gameToDelete = game
            showingDeleteAlert = true
        } label: {
            Label(NSLocalizedString("library.delete", comment: ""), systemImage: "trash")
        }
    }
}

#Preview {
    GameLibraryView()
        .preferredColorScheme(.dark)
}
