import SwiftUI

/// 8 colored pill tabs matching the CSS tab bar
struct TabBarView: View {
    @Binding var selectedTab: TabMode

    var body: some View {
        HStack(spacing: 3) {
            ForEach(TabMode.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.bgPrimary)
        .overlay(alignment: .bottom) {
            Divider().background(Theme.border)
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: TabMode) -> some View {
        let isActive = selectedTab == tab
        Button {
            selectedTab = tab
        } label: {
            Text(tab.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isActive ? activeTextColor(tab) : Theme.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? activeBackground(tab) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.pillRadius))
        }
        .buttonStyle(.plain)
    }

    private func activeTextColor(_ tab: TabMode) -> Color {
        switch tab {
        case .all:         return Theme.textPrimary
        case .transcribe:  return Theme.green
        case .greppy:      return Theme.purple
        case .cleanup:     return Theme.orange
        case .plan:        return Theme.blue
        case .analytics:   return Theme.chartAccent
        case .microphone:  return Theme.microphoneColor
        case .dictionary:  return Theme.dictionaryColor
        }
    }

    private func activeBackground(_ tab: TabMode) -> Color {
        switch tab {
        case .all:         return Theme.bgTertiary
        case .transcribe:  return Theme.greenSoft
        case .greppy:      return Theme.purpleSoft
        case .cleanup:     return Theme.orangeSoft
        case .plan:        return Theme.blueSoft
        case .analytics:   return Theme.chartAccent.opacity(0.15)
        case .microphone:  return Theme.microphoneSoft
        case .dictionary:  return Theme.dictionarySoft
        }
    }
}
