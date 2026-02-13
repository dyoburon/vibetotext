import SwiftUI

/// Scrollable list of entry cards
struct HistoryListView: View {
    let entries: [HistoryEntry]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(entries.prefix(100)) { entry in
                    EntryCardView(entry: entry)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 8)),
                            removal: .opacity
                        ))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}
