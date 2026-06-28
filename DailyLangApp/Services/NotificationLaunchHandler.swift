import Foundation
import Combine
import UIKit
import UserNotifications

@MainActor
final class NotificationLaunchHandler: NSObject, ObservableObject {
    static let shared = NotificationLaunchHandler()

    @Published var shouldOpenCamera = false

    private override init() {
        super.init()
    }

    func consumeCameraLaunchRequest() {
        shouldOpenCamera = false
    }

    fileprivate func requestCameraLaunch() {
        shouldOpenCamera = true
    }
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
        guard response.notification.request.content.categoryIdentifier == NotificationCategory.captureScene else {
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
        [.banner, .sound]
    }
}

enum NotificationCategory {
    static let captureScene = "CAPTURE_SCENE"

    static func makeCaptureSceneCategory() -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: captureScene,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
    }
}
