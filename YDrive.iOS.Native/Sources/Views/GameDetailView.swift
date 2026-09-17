import SwiftUI

struct GameDetailView: View {
    let game: GameItem
    @ObservedObject var viewModel: GameLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingGame = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        .black, Color(hex: "080E1C"),
                        Color(hex: "060B16"), Color(hex: "0B1428"),
                        .black, Color(hex: "06090F")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {

                        // ── Cover art ──
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color(hex: "0C1220"))
                                .frame(width: 210, height: 270)

                            if let path = game.coverImagePath,
                               let img = UIImage(contentsOfFile: path) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 210, height: 270)
                                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            } else {
                                Image(systemName: "gamecontroller.fill")
                                    .font(.system(size: 64))
                                    .foregroundStyle(.blue.gradient.opacity(0.5))
                            }
                        }
                        .shadow(color: .blue.opacity(0.25), radius: 30, y: 12)
                        .padding(.top, 8)

                        // ── Title ──
                        VStack(spacing: 10) {
                            Text(game.title)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)

                            Text(game.consoleName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .glassEffect(in: Capsule())
                        }

                        // ── Play button (iOS 26 prominent glass) ──
                        Button {
                            showingGame = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "play.fill")
                                Text("Oyna")
                                    .fontWeight(.bold)
                            }
                            .font(.system(size: 18))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                        }
                        .buttonStyle(.glass)
                        .tint(.blue)
                        .padding(.horizontal, 16)

                        // ── Info panel ──
                        VStack(alignment: .leading, spacing: 16) {
                            infoRow(icon: "person.fill",
                                    label: "Yapımcı",
                                    value: game.developer ?? "Bilinmiyor")
                            Divider().background(.white.opacity(0.08))

                            infoRow(icon: "calendar",
                                    label: "Çıkış Yılı",
                                    value: game.releaseYear ?? "Bilinmiyor")
                            Divider().background(.white.opacity(0.08))

                            infoRow(icon: "doc.fill",
                                    label: "Dosya",
                                    value: game.fileName)

                            if let summary = game.summary {
                                Divider().background(.white.opacity(0.08))
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
                        .padding(18)
                        // iOS 26: glass panel
                        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .fullScreenCover(isPresented: $showingGame) {
            EmulatorView(game: game)
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 22)
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
