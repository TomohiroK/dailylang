import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationLaunchHandler: NotificationLaunchHandler

    @AppStorage(AppStorageKey.notificationStartHour) private var startHour = AppDefaults.notificationStartHour
    @AppStorage(AppStorageKey.notificationEndHour) private var endHour = AppDefaults.notificationEndHour
    @AppStorage(AppStorageKey.dailyNotificationCount) private var dailyNotificationCount = AppDefaults.dailyNotificationCount

    @State private var selectedTab: RootTab

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        Self.applyLaunchSettingOverrides(arguments: arguments)
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
            await runLaunchDiagnosticsIfRequested()
        }
        .alert(item: $notificationLaunchHandler.foregroundPrompt) { prompt in
            Alert(
                title: Text(prompt.title),
                message: Text(prompt.body),
                primaryButton: .default(Text("写真を撮る")) {
                    notificationLaunchHandler.openCameraFromForegroundPrompt()
                },
                secondaryButton: .cancel(Text("閉じる")) {
                    notificationLaunchHandler.dismissForegroundPrompt()
                }
            )
        }
    }

    private func selectHomeForPendingCameraLaunch() {
        guard notificationLaunchHandler.shouldOpenCamera else {
            return
        }
        selectedTab = .home
    }

    @MainActor
    private func runLaunchDiagnosticsIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(AppLaunchArgument.exportDiagnostics)
                || arguments.contains(AppLaunchArgument.scheduleRandomNotifications)
                || arguments.contains(AppLaunchArgument.scheduleTestNotification)
        else {
            return
        }

        _ = try? KeychainAPIKeyStore().seedFromEnvironmentIfAvailable()
        let launchItems = await runNotificationLaunchActions(arguments: arguments)

        guard arguments.contains(AppLaunchArgument.exportDiagnostics) else {
            return
        }

        _ = try? await DiagnosticsExportService(modelContext: modelContext)
            .exportLatest(extraItems: launchItems)
    }

    @MainActor
    private func runNotificationLaunchActions(arguments: [String]) async -> [DiagnosticsExportItem] {
        let scheduler = NotificationScheduler()
        var items: [DiagnosticsExportItem] = []
        var didChangeNotifications = false

        if arguments.contains(AppLaunchArgument.scheduleRandomNotifications) {
            do {
                let summary = try await scheduler.scheduleRandomPrompts(
                    startHour: startHour,
                    endHour: endHour,
                    countPerDay: dailyNotificationCount
                )
                items.append(DiagnosticsExportItem(
                    id: "launch-schedule-random-notifications",
                    title: "起動時通知予約",
                    detail: summary.statusMessage,
                    status: "ready"
                ))
                didChangeNotifications = true
            } catch {
                items.append(DiagnosticsExportItem(
                    id: "launch-schedule-random-notifications",
                    title: "起動時通知予約",
                    detail: error.localizedDescription,
                    status: "blocked"
                ))
            }
        }

        if arguments.contains(AppLaunchArgument.scheduleTestNotification) {
            do {
                try await scheduler.scheduleTestPrompt()
                items.append(DiagnosticsExportItem(
                    id: "launch-schedule-test-notification",
                    title: "起動時テスト通知予約",
                    detail: "5秒後のテスト通知をpendingに確認しました。",
                    status: "ready"
                ))
                didChangeNotifications = true
            } catch {
                items.append(DiagnosticsExportItem(
                    id: "launch-schedule-test-notification",
                    title: "起動時テスト通知予約",
                    detail: error.localizedDescription,
                    status: "blocked"
                ))
            }
        }

        if didChangeNotifications {
            NotificationCenter.default.post(name: .dailyLangNotificationScheduleDidChange, object: nil)
        }

        return items
    }

    private static func applyLaunchSettingOverrides(arguments: [String]) {
        if arguments.contains(AppLaunchArgument.showNotificationTimes) {
            UserDefaults.standard.set(true, forKey: AppStorageKey.showNotificationTimes)
        }
        if arguments.contains(AppLaunchArgument.hideNotificationTimes) {
            UserDefaults.standard.set(false, forKey: AppStorageKey.showNotificationTimes)
        }
    }
}

private enum RootTab: Hashable {
    case home
    case review
    case settings
}

extension Notification.Name {
    static let dailyLangNotificationScheduleDidChange = Notification.Name("DailyLangNotificationScheduleDidChange")
}

#Preview {
    ContentView()
        .environmentObject(NotificationLaunchHandler.shared)
}
