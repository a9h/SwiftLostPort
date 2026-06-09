import SwiftUI

/// Reveals text character-by-character, echoing the original's
/// terminal typewriter effect.
struct TypewriterText: View {
    let text: String
    var speed: Duration = .milliseconds(16)

    @State private var visibleCount = 0

    var body: some View {
        // Layout against the full text so the view doesn't reflow as it types.
        Text(text)
            .hidden()
            .overlay(alignment: .topLeading) {
                Text(String(text.prefix(visibleCount)))
            }
            .task(id: text) {
                visibleCount = 0
                while visibleCount < text.count {
                    try? await Task.sleep(for: speed)
                    if Task.isCancelled { return }
                    visibleCount += 1
                }
            }
    }
}

extension View {
    /// Card backdrop used across the game's panels.
    func lostPanel() -> some View {
        padding(12)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
