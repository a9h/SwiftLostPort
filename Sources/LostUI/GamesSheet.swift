import SwiftUI
import GameCore

/// "The games available are: 50/50, H/L"
struct GamesSheet: View {
    @Environment(GameState.self) private var game
    @Environment(\.dismiss) private var dismiss
    @State private var pickedGame = 0

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("🎲 Trader's Games")
                    .font(.system(.title3, design: .monospaced).bold())
                Spacer()
                Text("💷 £\(game.player.money)")
                    .font(.callout.monospaced().bold())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: game.player.money)
                Button("Done") { dismiss() }
            }

            Picker("Game", selection: $pickedGame) {
                Text("50/50").tag(0)
                Text("H/L").tag(1)
            }
            .pickerStyle(.segmented)

            if pickedGame == 0 {
                CoinFlipView()
            } else {
                HigherLowerView()
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

// MARK: - 50/50

struct CoinFlipView: View {
    @Environment(GameState.self) private var game
    @State private var choice: CoinSide = .heads
    @State private var betText = "10"
    @State private var spinning = false
    @State private var result: GambleResult?

    var body: some View {
        VStack(spacing: 14) {
            Text("Pick a side, place a bet. Win pays 1.5×.")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

            Text("🪙")
                .font(.system(size: 72))
                .rotation3DEffect(.degrees(spinning ? 1080 : 0), axis: (x: 1, y: 0, z: 0))
                .animation(.easeOut(duration: 0.8), value: spinning)

            Picker("Side", selection: $choice) {
                Text("Heads").tag(CoinSide.heads)
                Text("Tails").tag(CoinSide.tails)
            }
            .pickerStyle(.segmented)

            BetField(betText: $betText, maxBet: game.player.money)

            Button {
                guard let bet = Int(betText) else { return }
                spinning.toggle()
                result = game.playCoinFlip(choice: choice, bet: bet)
            } label: {
                Label("Flip!", systemImage: "centsign.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .disabled(Int(betText) == nil)

            if let result {
                ResultBanner(result: result, playAgain: { self.result = nil })
            }
        }
        .lostPanel()
    }
}

// MARK: - H/L

struct HigherLowerView: View {
    @Environment(GameState.self) private var game
    @State private var betText = "10"
    @State private var exactText = ""
    @State private var result: GambleResult?

    var body: some View {
        VStack(spacing: 14) {
            Text("A secret number 1–100 is chosen. You get a hint from the same half. Right call pays 1.5× — naming the exact number pays 8×.")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

            if let round = game.hlRound {
                VStack(spacing: 10) {
                    Text("Hint: \(round.hint)")
                        .font(.system(size: 40, design: .monospaced).bold())
                        .foregroundStyle(.cyan)
                    Text("Bet: £\(round.bet) — is the secret higher or lower?")
                        .font(.callout.monospaced())

                    HStack(spacing: 10) {
                        Button { resolve(.higher) } label: {
                            Label("Higher", systemImage: "arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        Button { resolve(.lower) } label: {
                            Label("Lower", systemImage: "arrow.down").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }

                    HStack {
                        TextField("Exact guess (8×)", text: $exactText)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 160)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Button("Call it!") {
                            if let number = Int(exactText) { resolve(.exact(number)) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(Int(exactText) == nil)
                    }
                }
            } else {
                BetField(betText: $betText, maxBet: game.player.money)
                Button {
                    guard let bet = Int(betText) else { return }
                    if game.startHigherLower(bet: bet) { result = nil }
                } label: {
                    Label("Deal me in", systemImage: "questionmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(Int(betText) == nil)

                if let result {
                    ResultBanner(result: result, playAgain: { self.result = nil })
                }
            }
        }
        .lostPanel()
    }

    private func resolve(_ guess: HLGuess) {
        result = game.guessHigherLower(guess)
        exactText = ""
    }
}

// MARK: - Shared bits

struct BetField: View {
    @Binding var betText: String
    let maxBet: Int

    var body: some View {
        HStack {
            Text("Bet £").font(.callout.monospaced())
            TextField("amount", text: $betText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 110)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Button("Max (£\(maxBet))") { betText = String(maxBet) }
                .buttonStyle(.bordered)
                .font(.caption.monospaced())
        }
    }
}

struct ResultBanner: View {
    let result: GambleResult
    let playAgain: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(result.won ? (result.exact ? "🎉 EXACT MATCH! +£\(result.netChange)" : "✅ You won £\(result.netChange)!")
                            : "❌ You lost £\(-result.netChange)")
                .font(.callout.monospaced().bold())
                .foregroundStyle(result.won ? .green : .red)
            Text("(\(result.reveal))")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Button("Play again") { playAgain() }
                .buttonStyle(.bordered)
                .font(.caption.monospaced())
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background((result.won ? Color.green : Color.red).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .transition(.scale.combined(with: .opacity))
    }
}
