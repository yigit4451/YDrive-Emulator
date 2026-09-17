import SwiftUI

struct GameDetailView: View {
    let game: GameItem
    @ObservedObject var viewModel: GameLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingGame = false

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(white: 0.05), Color(white: 0.09)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {

                    // ── Cover Art ──
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(white: 0.12))
                            .frame(width: 200, height: 260)

                        if let path = game.coverImagePath,
                           let img = UIImage(contentsOfFile: path) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 200, height: 260)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        } else {
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.white.opacity(0.2))
                        }
                    }
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                    .padding(.top, 20)

                    // ── Title & Console ──
                    VStack(spacing: 8) {
                        Text(game.title)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        Text(game.consoleName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(.blue.opacity(0.18))
                            .clipShape(Capsule())
                    }

                    // ── Play Button ──
                    Button {
                        showingGame = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                            Text("Oyna")
                                .fontWeight(.bold)
                        }
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.blue, Color(red: 0, green: 0.55, blue: 1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .blue.opacity(0.4), radius: 12, y: 6)
                    }
                    .padding(.horizontal, 16)

                    // ── Info Card (Liquid Glass) ──
                    VStack(alignment: .leading, spacing: 14) {
                        infoRow(icon: "person.fill",
                                label: "Yapımcı",
                                value: game.developer ?? "Bilinmiyor")
                        Divider().background(.white.opacity(0.1))
                        infoRow(icon: "calendar",
                                label: "Çıkış Yılı",
                                value: game.releaseYear ?? "Bilinmiyor")
                        Divider().background(.white.opacity(0.1))
                        infoRow(icon: "doc.fill",
                                label: "Dosya",
                                value: game.fileName)
                        if let summary = game.summary {
                            Divider().background(.white.opacity(0.1))
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Özet")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(summary)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationBarHidden(true)
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
        }
        .fullScreenCover(isPresented: $showingGame) {
            EmulatorView(game: game)
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}
