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
        GridItem(.adaptive(minimum: 155, maximum: 195), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                // ── iOS 26 MeshGradient background ──
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                        [0.0, 0.5], [0.5, 0.4], [1.0, 0.5],
                        [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                    ],
                    colors: [
                        .black,         Color(hex: "0A0E1A"), .black,
                        Color(hex: "070B18"), Color(hex: "0D1830"), Color(hex: "050912"),
                        .black,         Color(hex: "08101F"), .black
                    ]
                )
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.isFilePickerPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    // iOS 26: glass button style
                    .buttonStyle(.glass)
                }
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
    }

    // MARK: – Empty State
    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            // iOS 26 glassEffect on the icon container
            ZStack {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue.gradient)
            }
            .padding(32)
            .glassEffect(in: Circle())

            Text("Kütüphanede Oyun Yok")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Genesis / Mega Drive ROM dosyası\n(.md .bin .gen .zip) ekleyin")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                viewModel.isFilePickerPresented = true
            } label: {
                Label("ROM Ekle", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
            }
            // iOS 26 glass button
            .buttonStyle(.glass)
            .tint(.blue)

            Spacer()
        }
        .padding(32)
    }

    // MARK: – Game Grid
    private var gameGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
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
        .scrollIndicators(.hidden)
    }
}

// MARK: – Color hex helper
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    GameLibraryView()
        .preferredColorScheme(.dark)
}
