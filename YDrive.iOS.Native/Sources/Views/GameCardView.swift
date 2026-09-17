import SwiftUI

struct GameCardView: View {
    let game: GameItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Cover art ──
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        MeshGradient(
                            width: 2, height: 2,
                            points: [[0,0],[1,0],[0,1],[1,1]],
                            colors: [
                                Color(hex: "0E1525"), Color(hex: "0A1020"),
                                Color(hex: "080D1A"), Color(hex: "060A14")
                            ]
                        )
                    )
                    .frame(height: 130)

                if let coverPath = game.coverImagePath,
                   let uiImage = UIImage(contentsOfFile: coverPath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 130)
                        .clipped()
                } else {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue.opacity(0.35))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.bottom, 10)

            // ── Title ──
            Text(game.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .padding(.bottom, 6)

            // ── Console badge ──
            Text(game.consoleName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .glassEffect(in: Capsule())  // iOS 26: glass capsule badge

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 210)
        // iOS 26: full-card liquid glass
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    GameCardView(game: GameItem(
        title: "Sonic the Hedgehog 2",
        consoleName: "SEGA Genesis",
        fileName: "sonic2.bin"
    ))
    .frame(width: 175)
    .padding()
    .background(.black)
    .preferredColorScheme(.dark)
}
