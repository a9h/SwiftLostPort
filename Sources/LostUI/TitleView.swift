import SwiftUI
import GameCore

/// Start screen: the old box-drawing logo rendered as styled SwiftUI,
/// with New Game / Continue.
struct TitleView: View {
    @EnvironmentObject private var game: GameState
    @State private var showLoadPicker = false
    @State private var showDebug = false
    @State private var showLifetimeStats = false

    private let logo = """
    ╔══════════════════════╗
    ║   L  O  S  T   🚪    ║
    ╚══════════════════════╝
    """

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 10) {
                Text(logo)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
                    .shadow(color: .green.opacity(0.6), radius: 12)
                    .onLongPressGesture(minimumDuration: 1.2) { showDebug = true }
                Text("Welcome to lost")
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                Button {
                    game.startNewGame()
                } label: {
                    Label("New Game", systemImage: "play.fill")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)

                Button {
                    showLoadPicker = true
                } label: {
                    Label("Continue", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!GameState.saveSlots.contains(where: { game.hasSave(slot: $0) }))

                Button {
                    game.refreshLifetimeStats()
                    showLifetimeStats = true
                } label: {
                    Label("Lifetime Stats", systemImage: "chart.bar.fill")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Text("🧟  🔦  🍅  🪖  🐉")
                .font(.title2)
                .opacity(0.7)

            Spacer()
            Text("A port of a tiny terminal roguelike")
                .font(.footnote.monospaced())
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)
        }
        .padding()
        .confirmationDialog("Load which save?", isPresented: $showLoadPicker, titleVisibility: .visible) {
            ForEach(GameState.saveSlots, id: \.self) { slot in
                if game.hasSave(slot: slot) {
                    Button(slotLabel(slot)) { _ = game.loadGame(slot: slot) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showDebug) { DebugSheet() }
        .sheet(isPresented: $showLifetimeStats) {
            LifetimeStatsSheet().environmentObject(game)
                #if os(macOS)
                .frame(minWidth: 380, minHeight: 420)
                #endif
        }
    }

    private func slotLabel(_ slot: Int) -> String {
        if let date = game.savedAt(slot: slot) {
            return "Slot \(slot) — \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Slot \(slot)"
    }
}
