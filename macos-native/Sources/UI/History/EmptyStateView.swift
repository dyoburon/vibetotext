import SwiftUI

/// Microphone icon + hint when no transcriptions exist
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "mic")
                .font(.system(size: 48))
                .foregroundColor(Theme.textMuted.opacity(0.3))

            VStack(spacing: 4) {
                Text("No transcriptions yet")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textMuted)

                Text("ctrl+shift to record")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.textMuted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
