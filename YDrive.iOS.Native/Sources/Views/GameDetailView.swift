import SwiftUI

struct GameDetailView: View {
    let game: GameItem
    var viewModel: GameLibraryViewModel? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showingGame = false

    var body: some View {
        ZStack(alignment: .top) {
            // Background Content Area
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    
                    Color.clear.frame(height: 60) // Safe area for floating top bar
                    
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
                                    label: "Yapımcı",
                                    value: developer)
                            Divider()
                        }

                        if let releaseYear = game.releaseYear {
                            infoRow(icon: "calendar",
                                    label: "Çıkış Yılı",
                                    value: releaseYear)
                            Divider()
                        }

                        infoRow(icon: "doc.fill",
                                label: "Dosya",
                                value: URL(fileURLWithPath: game.fileName).lastPathComponent)

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
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 24)
                    
                    Color.clear.frame(height: 100) // Padding for floating play button
                }
            }
            .ignoresSafeArea(edges: .bottom)

            // ── Floating Top Bar ──
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.primary)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

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
