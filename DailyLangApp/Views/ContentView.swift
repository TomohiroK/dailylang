import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationLaunchHandler: NotificationLaunchHandler

    @State private var selectedTab: RootTab

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        _selectedTab = State(initialValue: arguments.contains(AppLaunchArgument.openSettings) ? .settings : .home)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(RootTab.home)

            ReviewView()
                .tabItem {
                    Label("Review", systemImage: "rectangle.stack")
                }
                .tag(RootTab.review)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(RootTab.settings)
        }
        .onAppear {
            selectHomeForPendingCameraLaunch()
        }
        .onChange(of: notificationLaunchHandler.shouldOpenCamera) { _, shouldOpenCamera in
            guard shouldOpenCamera else {
                return
            }
            selectHomeForPendingCameraLaunch()
        }
        .task {
            await exportDiagnosticsIfRequested()
        }
    }

    private func selectHomeForPendingCameraLaunch() {
        guard notificationLaunchHandler.shouldOpenCamera else {
            return
        }
        selectedTab = .home
    }

    @MainActor
    private func exportDiagnosticsIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains(AppLaunchArgument.exportDiagnostics) else {
            return
        }

        _ = try? KeychainAPIKeyStore().seedFromEnvironmentIfAvailable()
        _ = try? await DiagnosticsExportService(modelContext: modelContext).exportLatest()
    }
}

private enum RootTab: Hashable {
    case home
    case review
    case settings
}

#Preview {
    ContentView()
        .environmentObject(NotificationLaunchHandler.shared)
}
