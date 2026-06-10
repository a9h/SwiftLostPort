import SwiftUI
import GameCore

/// The app's single entry view: switches on `GameState.screen`.
public struct LostRootView: View {
    @StateObject private var game: GameState

    public init(game: GameState = GameState()) {
        _game = StateObject(wrappedValue: game)
    }

    public var body: some View {
        ZStack {
            background

            switch game.screen {
            case .title:
                TitleView()
                    .transition(.opacity)
            case .room, .encounter, .trader:
                GameplayView()
                    .transition(.opacity)
            case .gameOver(let reason, let money):
                GameOverView(reason: reason, money: money)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: screenKey)
        .environmentObject(game)
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 700)
        #endif
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.07, green: 0.08, blue: 0.12), Color(red: 0.12, green: 0.10, blue: 0.18)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    /// Coarse key so screen switches animate but in-screen changes don't.
    private var screenKey: Int {
        switch game.screen {
        case .title: return 0
        case .room: return 1
        case .encounter: return 2
        case .trader: return 3
        case .gameOver: return 4
        }
    }
}
