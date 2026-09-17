import SwiftUI

struct GameCardView: View {
    let game: GameItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Cover art area ──
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.12),
                                Color(white: 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 140)

                if let coverPath = game.coverImagePath,
                   let uiImage = UIImage(contentsOfFile: coverPath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 140)
                        .clipped()
                } else {
                    // Placeholder
                    VStack(spacing: 8) {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 36))
                            .foregroundStyle(.white.opacity(0.25))
                        Text("No Cover")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.2))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.bottom, 10)

            // ── Game Title ──
            Text(game.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.bottom, 4)

            // ── Console chip ──
            Text(game.consoleName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.blue.opacity(0.15))
                .clipShape(Capsule())

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 220)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
}

#Preview {
    GameCardView(game: GameItem(
        title: "Sonic the Hedgehog 2",
        consoleName: "SEGA Genesis",
        fileName: "sonic2.bin",
        developer: "Sega"
    ))
    .frame(width: 180)
    .padding()
    .background(Color(white: 0.06))
    .preferredColorScheme(.dark)
}
