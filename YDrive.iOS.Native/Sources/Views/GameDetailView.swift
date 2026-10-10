import SwiftUI
import PhotosUI

struct GameDetailView: View {
    let initialGame: GameItem
    @ObservedObject var viewModel: GameLibraryViewModel
    var isPresentedFromEmulator: Bool = false
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingGame = false
    @State private var showingRenameAlert = false
    @State private var renameText = ""
    @State private var showingDeleteAlert = false
    @State private var playingGame: GameItem?
    @State private var showingCoverPicker = false
    @State private var selectedCoverItem: PhotosPickerItem?
    
    var game: GameItem {
        viewModel.games.first(where: { $0.id == initialGame.id }) ?? initialGame
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    
                    // ── Cover art ──
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(white: 0.15))
                            .frame(width: 220, height: 290)

                        if let path = game.coverImagePath {
                            let filename = URL(fileURLWithPath: path).lastPathComponent
                            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            let resolvedPath = docs.appendingPathComponent(filename).path
                            
                            if let img = UIImage(contentsOfFile: resolvedPath) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 220, height: 290)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            } else {
                                Image(systemName: "gamecontroller.fill")
                                    .font(.system(size: 72))
                                    .foregroundStyle(.tertiary)
                            }
                        } else {
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .shadow(color: .black.opacity(0.2), radius: 15, y: 8)

                    // ── Title & Console ──
                    VStack(spacing: 8) {
                        Text(game.title)
                            .font(.title.weight(.bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)

                        Text(game.consoleName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal)

                    // ── Info panel ──
                    VStack(alignment: .leading, spacing: 16) {
                        if let developer = game.developer {
                            infoRow(icon: "person.fill",
                                    label: "Developer",
                                    value: developer)
                            Divider()
                        }

                        if let releaseYear = game.releaseYear {
                            infoRow(icon: "calendar",
                                    label: "Release Year",
                                    value: releaseYear)
                            Divider()
                        }

                        infoRow(icon: "doc.fill",
                                label: "File",
                                value: URL(fileURLWithPath: game.fileName).lastPathComponent)

                        if let summary = game.summary {
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Summary")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .padding(20)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 24)
                    Color.clear.frame(height: 40) // Padding for bottom
                }
                .padding(.top, 24)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .fontWeight(.semibold)
                    }
                    .tint(.primary)
                }
                if !isPresentedFromEmulator {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            renameText = game.title
                            showingRenameAlert = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .tint(.primary)
                        
                        Button {
                            showingCoverPicker = true
                        } label: {
                            Image(systemName: "photo.on.rectangle")
                        }
                        .accessibilityLabel("Change Cover")
                        .tint(.primary)
                        
                        Button {
                            showingDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                        
                        Button {
                            Task {
                                await viewModel.fetchMetadata(for: game.id)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .tint(.blue)
                        
                        Button {
                            playingGame = game
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .photosPicker(isPresented: $showingCoverPicker, selection: $selectedCoverItem, matching: .images, photoLibrary: .shared())
        .onChange(of: selectedCoverItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    viewModel.updateCoverImageData(for: game, imageData: data)
                }
                selectedCoverItem = nil
            }
        }
        .alert("Rename", isPresented: $showingRenameAlert) {
            TextField("New name", text: $renameText)
            Button("Save") {
                if !renameText.isEmpty {
                    viewModel.renameGame(game, to: renameText)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Are you sure you want to delete?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.deleteGame(game)
                dismiss()
            }
        }
        .fullScreenCover(item: $playingGame) { gameItem in
            EmulatorView(game: gameItem, viewModel: viewModel)
        }
    }

    private func infoRow(icon: String, label: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.body)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}
