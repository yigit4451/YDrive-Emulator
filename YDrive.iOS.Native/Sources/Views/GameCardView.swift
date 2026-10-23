import SwiftUI

struct GameCardView: View {
    let game: GameItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // ── Cover art ──
            ZStack {
                if let uiImage = game.resolveCoverImage() {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 140)
                        .clipped()
                } else {
                    ZStack {
                        Color(UIColor.secondarySystemFill)
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(consoleColor.opacity(0.85))
                    }
                    .frame(height: 140)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding([.horizontal, .top], 8)
            .padding(.bottom, 10)

            // ── Title ──
            Text(game.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            // ── Console badge ──
            HStack(spacing: 5) {
                Circle()
                    .fill(consoleColor)
                    .frame(width: 6, height: 6)
                Text(game.consoleName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            Spacer(minLength: 0)
        }
        .frame(minHeight: 230, alignment: .top)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var consoleColor: Color {
        switch game.consoleName {
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
}

#Preview {
    GameCardView(game: GameItem(
        title: "Sonic the Hedgehog 2",
        consoleName: "SEGA Genesis",
        fileName: "sonic2.bin"
    ))
    .frame(width: 175)
    .padding()
    .background(Color(red: 0.05, green: 0.05, blue: 0.1))
    .preferredColorScheme(.dark)
}
