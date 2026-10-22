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

    /// Red gallery icon with an xmark below it, used for "Remove Artwork" in the card menu.
    private static let removeArtworkIcon: UIImage = {
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let xCfg = UIImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        let photo = UIImage(systemName: "photo.on.rectangle", withConfiguration: cfg)?
            .withTintColor(.systemRed, renderingMode: .alwaysOriginal)
        let xmark = UIImage(systemName: "xmark", withConfiguration: xCfg)?
            .withTintColor(.systemRed, renderingMode: .alwaysOriginal)
        guard let photo, let xmark else { return UIImage() }
        let size = CGSize(width: max(photo.size.width, xmark.size.width),
                          height: photo.size.height + xmark.size.height + 1)
        let img = UIGraphicsImageRenderer(size: size).image { _ in
            photo.draw(at: CGPoint(x: (size.width - photo.size.width) / 2, y: 0))
            xmark.draw(at: CGPoint(x: (size.width - xmark.size.width) / 2, y: photo.size.height + 1))
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
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
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
                .onAppear {
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
                VStack(spacing: 0) {
                    topBarHeader

                    ScrollView {
                        if viewMode == "grid" {
                            gameGrid
                        } else {
                            gameList
                        }
                    }
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: – Top Bar Header
    private var topBarHeader: some View {
        HStack {
            Spacer()
            viewModeBox
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var viewModeBox: some View {
        HStack(spacing: 8) {
            Button {
                guard viewMode != "grid" else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    viewMode = "grid"
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: viewMode == "grid" ? "square.grid.2x2.fill" : "square.grid.2x2")
                    .font(.system(size: 14, weight: viewMode == "grid" ? .bold : .medium))
                    .foregroundColor(viewMode == "grid" ? Color.accentColor : Color.secondary)
                    .frame(width: 36, height: 30)
                    .background(
                        Capsule()
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        Capsule()
                            .stroke(viewMode == "grid" ? Color.accentColor : Color(UIColor.separator).opacity(0.6), lineWidth: viewMode == "grid" ? 1.5 : 0.8)
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(NSLocalizedString("library.grid_view", comment: "")))

            Button {
                guard viewMode != "list" else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    viewMode = "list"
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 14, weight: viewMode == "list" ? .bold : .medium))
                    .foregroundColor(viewMode == "list" ? Color.accentColor : Color.secondary)
                    .frame(width: 36, height: 30)
                    .background(
                        Capsule()
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        Capsule()
                            .stroke(viewMode == "list" ? Color.accentColor : Color(UIColor.separator).opacity(0.6), lineWidth: viewMode == "list" ? 1.5 : 0.8)
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(NSLocalizedString("library.list_view", comment: "")))
        }
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
                if let coverPath = game.coverImagePath,
                   let uiImage = UIImage(contentsOfFile: coverPath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "gamecontroller.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )

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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 2)
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
            showingDetailsForGame = game
        } label: {
            Label("Game Info", systemImage: "info.circle")
        }
        
        Button {
            coverTarget = game
            showingCoverPicker = true
        } label: {
            Label("Change Cover", systemImage: "photo.on.rectangle")
        }

        if game.coverImagePath != nil {
            Button(role: .destructive) {
                viewModel.removeCoverImage(for: game)
            } label: {
                Label {
                    Text("Remove Artwork")
                } icon: {
                    Image(uiImage: Self.removeArtworkIcon)
                }
            }
        }
        
        Button {
            renameTarget = game
            renameText = game.title
            showingRenameAlert = true
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button(role: .destructive) {
            gameToDelete = game
            showingDeleteAlert = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

#Preview {
    GameLibraryView()
        .preferredColorScheme(.dark)
}
