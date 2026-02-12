import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selection: NavDestination?

    var body: some View {
        List(selection: $selection) {
            Section("Explore") {
                NavigationLink(value: NavDestination.galaxy) {
                    Label("Word Galaxy", systemImage: "sparkles")
                }
                NavigationLink(value: NavDestination.tree) {
                    Label("Frequency Tree", systemImage: "leaf")
                }
                NavigationLink(value: NavDestination.history(mode: nil)) {
                    Label("All History", systemImage: "clock")
                }
            }

            Section("Modes") {
                NavigationLink(value: NavDestination.history(mode: "transcribe")) {
                    HStack {
                        Label("Transcribe", systemImage: "mic")
                        Spacer()
                        Text("\(modeCount("transcribe"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                NavigationLink(value: NavDestination.history(mode: "plan")) {
                    HStack {
                        Label("Plan", systemImage: "list.bullet")
                        Spacer()
                        Text("\(modeCount("plan"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                NavigationLink(value: NavDestination.history(mode: "greppy")) {
                    HStack {
                        Label("Greppy", systemImage: "magnifyingglass")
                        Spacer()
                        Text("\(modeCount("greppy"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("VibeToText")
    }

    private func modeCount(_ mode: String) -> Int {
        appState.entries.filter { $0.mode == mode }.count
    }
}
