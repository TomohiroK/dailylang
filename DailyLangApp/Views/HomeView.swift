import SwiftData
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var notificationLaunchHandler: NotificationLaunchHandler
    @Query(sort: \LessonRecord.createdAt, order: .reverse) private var lessons: [LessonRecord]

    @AppStorage(AppStorageKey.dailyNotificationCount) private var dailyNotificationCount = AppDefaults.dailyNotificationCount

    @State private var isShowingCamera = false
    @State private var capturedPhoto: CapturedPhoto?
    @State private var pendingCapturedPhoto: CapturedPhoto?
    @State private var latestGeneratedLessonRecord: LessonRecord?
    @State private var pendingGeneratedLessonRecord: LessonRecord?
    @State private var didHandleLaunchSample = false

    private var visibleLessons: [LessonRecord] {
        lessons.filter(\.hasLearnerVisibleText)
    }

    private var todayLessonCount: Int {
        visibleLessons.filter { Calendar.current.isDateInToday($0.createdAt) }.count
    }

    private var latestLesson: LessonRecord? {
        if let latestGeneratedLessonRecord, latestGeneratedLessonRecord.hasLearnerVisibleText {
            return latestGeneratedLessonRecord
        }
        return visibleLessons.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        StatTile(title: "今日の通知", value: "\(dailyNotificationCount)")
                        StatTile(title: "今日のレッスン", value: "\(todayLessonCount)")
                    }

                    Button {
                        isShowingCamera = true
                    } label: {
                        Label("今すぐ撮る", systemImage: "camera.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)

                    if let latest = latestLesson {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("最新レッスン")
                                .font(.headline)

                            NavigationLink {
                                LessonDetailView(record: latest)
                            } label: {
                                LessonPreviewCard(record: latest)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        ContentUnavailableView(
                            "まだレッスンがありません",
                            systemImage: "text.book.closed",
                            description: Text("写真を撮ると、日常の場面からインドネシア語レッスンを作れます。")
                        )
                        .padding(.top, 24)
                    }
                }
                .padding()
            }
            .navigationTitle("DailyLang")
            .sheet(isPresented: $isShowingCamera, onDismiss: presentPendingCapturedPhoto) {
                CameraView { image in
                    pendingCapturedPhoto = CapturedPhoto(image: image)
                }
            }
            .sheet(item: $capturedPhoto, onDismiss: presentPendingGeneratedLesson) { photo in
                GeneratingView(photo: photo) { record in
                    pendingGeneratedLessonRecord = record
                }
            }
            .onAppear {
                openCameraIfRequested()
                openSampleIfRequestedByLaunchArgument()
            }
            .onChange(of: notificationLaunchHandler.shouldOpenCamera) { _, shouldOpenCamera in
                guard shouldOpenCamera else {
                    return
                }
                openCameraIfRequested()
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }

    private func openCameraIfRequested() {
        guard notificationLaunchHandler.shouldOpenCamera else {
            return
        }
        isShowingCamera = true
        notificationLaunchHandler.consumeCameraLaunchRequest()
    }

    private func presentPendingCapturedPhoto() {
        guard let pendingCapturedPhoto else {
            return
        }

        self.pendingCapturedPhoto = nil
        capturedPhoto = pendingCapturedPhoto
    }

    private func presentPendingGeneratedLesson() {
        guard let pendingGeneratedLessonRecord else {
            return
        }

        self.pendingGeneratedLessonRecord = nil
        latestGeneratedLessonRecord = pendingGeneratedLessonRecord
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "dailylang" else {
            return
        }

        if url.host == "sample" || url.path == "/sample" {
            capturedPhoto = CapturedPhoto(image: SampleSceneImageFactory.makeOfficeSceneImage())
        }
    }

    private func openSampleIfRequestedByLaunchArgument() {
        guard !didHandleLaunchSample else {
            return
        }

        didHandleLaunchSample = true
        guard ProcessInfo.processInfo.arguments.contains(AppLaunchArgument.sampleScene) else {
            return
        }

        capturedPhoto = CapturedPhoto(image: SampleSceneImageFactory.makeOfficeSceneImage())
    }
}

private struct StatTile: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct LessonPreviewCard: View {
    var record: LessonRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(record.mainSentenceID)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Text(record.mainSentenceJP)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)

            if record.favorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
