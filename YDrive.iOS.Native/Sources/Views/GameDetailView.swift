import SwiftUI

struct GameDetailView: View {
    let game: GameItem
    @ObservedObject var viewModel: GameLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingGame = false

    var body: some View {
        NavigationStack {
            ZStack {
                MeshGradient(
                    width: 2, height: 3,
                    points: [[0,0],[1,0],[0,0.5],[1,0.5],[0,1],[1,1]],
                    colors: [
                        Color(red: 0.0, green: 0.0, blue: 0.0), Color(red: 0.05, green: 0.1, blue: 0.2),
                        Color(red: 0.02, green: 0.05, blue: 0.1), Color(red: 0.1, green: 0.2, blue: 0.4),
                        Color(red: 0.0, green: 0.0, blue: 0.0), Color(red: 0.05, green: 0.1, blue: 0.2)
                    ]
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        
                        // ── Cover art ──
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(white: 0.15))
                                .frame(width: 220, height: 290)

                            if let path = game.coverImagePath,
                               let img = UIImage(contentsOfFile: path) {
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
                        }
                        .shadow(color: .black.opacity(0.3), radius: 15, y: 8)
                        .padding(.top, 24)

                        // ── Title & Console ──
                        VStack(spacing: 8) {
                            Text(game.title)
                                .font(.title.weight(.bold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)

                            Text(game.consoleName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(.blue.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal)

                        // ── Play button ──
                        Button {
                            showingGame = true
                        } label: {
                            Label("Oyna", systemImage: "play.fill")
                                .font(.title3.weight(.bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(Color.blue.opacity(0.8))
                        .padding(.horizontal, 24)

                        // ── Info panel ──
                        VStack(alignment: .leading, spacing: 16) {
                            infoRow(icon: "person.fill",
                                    label: "Yapımcı",
                                    value: game.developer ?? "Bilinmiyor")
                            Divider()

                            infoRow(icon: "calendar",
                                    label: "Çıkış Yılı",
                                    value: game.releaseYear ?? "Bilinmiyor")
                            Divider()

                            infoRow(icon: "doc.fill",
                                    label: "Dosya",
                                    value: game.fileName)

                            if let summary = game.summary {
                                Divider()
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Özet")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(summary)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        dismiss()
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingGame) {
            EmulatorView(game: game)
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
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
