import SwiftUI

struct GameCardView: View {
    let game: GameItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // ── Cover art with Liquid Glass inner bezel ──
            ZStack {
                if let uiImage = game.resolveCoverImage() {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 140)
                        .clipped()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [
                                consoleColor.opacity(0.35),
                                consoleColor.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(consoleColor.opacity(0.85))
                    }
                    .frame(height: 140)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.45), location: 0.0),
                                .init(color: .white.opacity(0.10), location: 0.4),
                                .init(color: .clear, location: 0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .padding([.horizontal, .top], 8)
            .padding(.bottom, 10)

            // ── Title ──
            Text(game.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            // ── Console badge (Liquid Glass Pill) ──
            HStack(spacing: 5) {
                Circle()
                    .fill(consoleColor)
                    .frame(width: 6, height: 6)
                Text(game.consoleName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(consoleColor.opacity(0.15))
                    Capsule().strokeBorder(consoleColor.opacity(0.35), lineWidth: 0.8)
                }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            Spacer(minLength: 0)
        }
        .frame(minHeight: 235, alignment: .top)
        // Liquid Glass Multi-Layer Background
        .background(
            ZStack {
                // 1. Frosted ultra thin material base
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)

                // 2. Liquid glass colored ambient wash
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                consoleColor.opacity(0.12),
                                Color.white.opacity(0.04),
                                consoleColor.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // 3. Diagonal specular reflection sheen
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.24), location: 0.0),
                                .init(color: .white.opacity(0.06), location: 0.35),
                                .init(color: .clear, location: 0.65)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        // Liquid specular edge border (Prism rim)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.70), location: 0.0),
                            .init(color: .white.opacity(0.25), location: 0.35),
                            .init(color: consoleColor.opacity(0.35), location: 0.70),
                            .init(color: .white.opacity(0.18), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        // Soft diffused depth shadow & glow
        .shadow(color: Color.black.opacity(0.20), radius: 12, x: 0, y: 6)
        .shadow(color: consoleColor.opacity(0.15), radius: 16, x: 0, y: 4)
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
