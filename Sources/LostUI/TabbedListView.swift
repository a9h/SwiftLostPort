import SwiftUI
import GameCore

/// Part 1 — the shared tabbed list UI. A horizontal row of pressable category
/// tabs (the selected one highlighted); tapping a tab instantly switches the
/// list shown below. Tabs scroll horizontally so they stay readable on a narrow
/// iPhone. Reused by the inventory, use menu, scavenger sell menu and the
/// Workbench (Part 2) — built once here.
struct TabbedPanel: View {
    struct Tab: Identifiable {
        let id: String
        let label: String
        let content: AnyView

        init<C: View>(id: String, label: String, @ViewBuilder content: () -> C) {
            self.id = id
            self.label = label
            self.content = AnyView(content())
        }
    }

    let tabs: [Tab]
    @State private var selectedID: String

    init(tabs: [Tab]) {
        self.tabs = tabs
        _selectedID = State(initialValue: tabs.first?.id ?? "")
    }

    private var selectedTab: Tab? {
        tabs.first { $0.id == selectedID } ?? tabs.first
    }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabs) { tab in
                        let isSelected = tab.id == selectedTab?.id
                        Button {
                            selectedID = tab.id
                        } label: {
                            Text(tab.label)
                                .font(.callout.monospaced())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSelected ? Color.green.opacity(0.25) : Color.gray.opacity(0.12))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Color.green : Color.clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }

            if let selectedTab {
                selectedTab.content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// A quiet placeholder for an empty tab (instead of a blank panel).
struct QuietPlaceholder: View {
    var text = "Nothing here yet."

    var body: some View {
        Text(text)
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }
}

/// A scrolling list of item rows for one tab, with the shared empty placeholder.
struct TabItemList<Row: View>: View {
    let items: [(id: String, count: Int)]
    let emptyText: String
    let row: (String, Int) -> Row

    init(items: [(id: String, count: Int)],
         emptyText: String = "Nothing here yet.",
         @ViewBuilder row: @escaping (_ id: String, _ count: Int) -> Row) {
        self.items = items
        self.emptyText = emptyText
        self.row = row
    }

    var body: some View {
        if items.isEmpty {
            QuietPlaceholder(text: emptyText)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(items, id: \.id) { item in
                        row(item.id, item.count)
                    }
                }
            }
        }
    }
}
