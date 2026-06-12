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
                .font(.system(size: 90))
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

            runStatsPanel

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

    /// This run's tracked stats (Lost update Part 4) plus the cause of death.
    private var runStatsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("THIS RUN")
                .font(.caption.monospaced().bold())
                .foregroundStyle(.tertiary)
            ForEach(game.runStats.labelledRows, id: \.label) { row in
                statRow(row.label, row.value)
            }
            Divider().overlay(Color.secondary.opacity(0.4))
            statRow("Cause of death", game.causeOfDeath.isEmpty ? reason : game.causeOfDeath)
        }
        .font(.callout.monospaced())
        .padding(14)
        .frame(maxWidth: 320)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold()
        }
    }
}
