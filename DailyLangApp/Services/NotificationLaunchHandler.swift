import Foundation
import Combine
import UIKit
import UserNotifications

@MainActor
final class NotificationLaunchHandler: NSObject, ObservableObject {
    static let shared = NotificationLaunchHandler()

    @Published var shouldOpenCamera = false
    @Published var foregroundPrompt: ForegroundNotificationPrompt?

    private override init() {
        super.init()
    }

    func consumeCameraLaunchRequest() {
        shouldOpenCamera = false
    }

    func dismissForegroundPrompt() {
        foregroundPrompt = nil
    }

    func openCameraFromForegroundPrompt() {
        foregroundPrompt = nil
        requestCameraLaunch()
    }

    fileprivate func requestCameraLaunch() {
        shouldOpenCamera = true
    }

    func presentForegroundPrompt(title: String, body: String) {
        foregroundPrompt = ForegroundNotificationPrompt(title: title, body: body)
    }
}

struct ForegroundNotificationPrompt: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var body: String
}

final class AppNotificationDelegate: NSObject, UIApplicationDelegate {
    private let notificationDelegate = NotificationCenterDelegate()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        center.setNotificationCategories([NotificationCategory.makeCaptureSceneCategory()])
        return true
    }
}

private final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard NotificationCategory.shouldOpenCamera(for: response.notification.request) else {
            return
        }

        await MainActor.run {
            NotificationLaunchHandler.shared.requestCameraLaunch()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if NotificationCategory.shouldOpenCamera(for: notification.request) {
            let title = notification.request.content.title.isEmpty ? "DailyLang" : notification.request.content.title
            let body = notification.request.content.body
            await MainActor.run {
                NotificationLaunchHandler.shared.presentForegroundPrompt(
                    title: title,
                    body: body
                )
            }
        }

        return [.banner, .list, .sound, .badge]
    }
}

enum NotificationCategory {
    static let captureScene = "CAPTURE_SCENE"

    static func shouldOpenCamera(for categoryIdentifier: String) -> Bool {
        categoryIdentifier == captureScene
    }

    static func shouldOpenCamera(for request: UNNotificationRequest) -> Bool {
        shouldOpenCamera(for: request.content.categoryIdentifier)
            || request.identifier.hasPrefix(NotificationIdentifier.scheduledPromptIdentifierPrefix)
            || request.identifier == NotificationIdentifier.testPromptIdentifier
    }

    static func makeCaptureSceneCategory() -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: captureScene,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
    }
}
