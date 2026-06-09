import SwiftUI
import GameCore

/// The message feed. The newest entry gets the typewriter animation;
/// older ones are dimmed history.
struct LogView: View {
    @Environment(GameState.self) private var game

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(game.log) { entry in
                        line(for: entry, isLatest: entry.id == game.log.last?.id)
                            .id(entry.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .onChange(of: game.log.last?.id) {
                if let id = game.log.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func line(for entry: LogEntry, isLatest: Bool) -> some View {
        Group {
            if isLatest {
                TypewriterText(text: entry.text)
            } else {
                Text(entry.text)
            }
        }
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(color(for: entry.kind).opacity(isLatest ? 1 : 0.62))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for kind: LogEntry.Kind) -> Color {
        switch kind {
        case .narration: return .primary
        case .info: return .secondary
        case .combat: return .orange
        case .warning: return .red
        case .reward: return .green
        }
    }
}
