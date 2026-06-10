import SwiftUI
import GameCore

struct GameOverView: View {
    @EnvironmentObject private var game: GameState
    let reason: String
    let money: Int
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("💀")
                .font(.system(size: 110))
                .scaleEffect(appeared ? 1 : 0.2)
                .animation(.bouncy(duration: 0.6), value: appeared)

            VStack(spacing: 8) {
                Text("GAME OVER")
                    .font(.system(size: 34, weight: .black, design: .monospaced))
                    .foregroundStyle(.red)
                TypewriterText(text: reason)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                Text("You died with 💷 £\(money)")
                    .font(.title3.monospaced().bold())
                    .padding(.top, 6)
            }

            VStack(spacing: 12) {
                Button {
                    game.startNewGame()
                } label: {
                    Label("Try Again", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)

                Button {
                    game.returnToTitle()
                } label: {
                    Text("Title Screen")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding()
        .onAppear { appeared = true }
    }
}
