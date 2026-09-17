import SwiftUI
import UniformTypeIdentifiers

// Supported ROM file types for import
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

    // 2-column adaptive grid
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    var body: some View {
        ZStack {
            // ── Full-screen frosted glass background ──
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.12),
                    Color(red: 0.08, green: 0.09, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Top App Bar ──
                topAppBar

                // ── Search Bar ──
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // ── Content ──
                if viewModel.filteredGames.isEmpty {
                    emptyState
                } else {
                    gameGrid
                }
            }
        }
        .navigationBarHidden(true)
        .fileImporter(
            isPresented: $viewModel.isFilePickerPresented,
            allowedContentTypes: romUTTypes.isEmpty ? [.data] : romUTTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                urls.forEach { viewModel.addRom(url: $0) }
            case .failure:
                break
            }
        }
        .alert("Oyunu Yeniden Adlandır", isPresented: $showingRenameAlert) {
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

    // MARK: – Top App Bar
    private var topAppBar: some View {
        HStack(spacing: 12) {
            // Logo
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(.blue.gradient)
                    .font(.system(size: 20, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("YDrive")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("SEGA Consoles Emulator")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.blue.opacity(0.8))
            }

            Spacer()

            // Settings
            NavigationLink(destination: SettingsView()) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.15), lineWidth: 1)
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 18))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.white.opacity(0.08)),
            alignment: .bottom
        )
    }

    // MARK: – Search Bar
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 16, weight: .medium))
            TextField("Oyun ara...", text: $viewModel.searchText)
                .foregroundStyle(.white)
                .tint(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: – Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                    .frame(width: 96, height: 96)
                Image(systemName: "gamecontroller")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue.opacity(0.8))
            }
            Text("Kütüphanede Oyun Yok")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Oynamak için Genesis / Mega Drive ROM\ndosyası (.md, .bin, .gen, .zip) ekleyin.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                viewModel.isFilePickerPresented = true
            } label: {
                Label("ROM Ekle", systemImage: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            Spacer()
        }
        .padding()
    }

    // MARK: – Game Grid
    private var gameGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                // "Add ROM" card
                Button {
                    viewModel.isFilePickerPresented = true
                } label: {
                    AddRomCardView()
                }

                // Game cards
                ForEach(viewModel.filteredGames) { game in
                    Button {
                        selectedGame = game
                    } label: {
                        GameCardView(game: game)
                    }
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
                            Label("ROM'u Sil", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: – Add ROM Card
private struct AddRomCardView: View {
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.blue.opacity(0.15))
                    .frame(height: 130)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue.gradient)
            }
            Text("ROM Ekle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.blue)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.blue.opacity(0.3), lineWidth: 1.5)
        )
    }
}

#Preview {
    NavigationStack {
        GameLibraryView()
    }
    .preferredColorScheme(.dark)
}
