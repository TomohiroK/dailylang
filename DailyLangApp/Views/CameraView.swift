import AVFoundation
import SwiftUI
import UIKit

struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let onCapture: (UIImage) -> Void

    @State private var cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        if !UIImagePickerController.isSourceTypeAvailable(.camera) {
            unavailableCamera
        } else if cameraAuthorizationStatus == .authorized {
            CameraPicker { image in
                onCapture(image)
                dismiss()
            } onCancel: {
                dismiss()
            }
            .ignoresSafeArea()
        } else {
            cameraPermissionView
                .task {
                    await requestCameraAccessIfNeeded()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else {
                        return
                    }
                    cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                }
        }
    }

    private var unavailableCamera: some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                "カメラを利用できません",
                systemImage: "camera",
                description: Text("実機でカメラ権限を許可して撮影してください。")
            )

            Button {
                onCapture(SampleSceneImageFactory.makeOfficeSceneImage())
                dismiss()
            } label: {
                Label("サンプルで生成", systemImage: "doc.text.image")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
        }
        .toolbar {
            Button("閉じる") {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var cameraPermissionView: some View {
        VStack(spacing: 20) {
            switch cameraAuthorizationStatus {
            case .notDetermined:
                ProgressView()
                Text("カメラ権限を確認しています")
                    .font(.headline)
            case .denied, .restricted:
                ContentUnavailableView(
                    "カメラを利用できません",
                    systemImage: "camera.fill",
                    description: Text("設定アプリでカメラを許可してください。")
                )
                Button {
                    openAppSettings()
                } label: {
                    Label("設定を開く", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
            case .authorized:
                EmptyView()
            @unknown default:
                ContentUnavailableView(
                    "カメラを利用できません",
                    systemImage: "camera",
                    description: Text("カメラ状態を確認できませんでした。")
                )
            }
        }
        .padding()
        .toolbar {
            Button("閉じる") {
                dismiss()
            }
        }
    }

    @MainActor
    private func requestCameraAccessIfNeeded() async {
        guard cameraAuthorizationStatus == .notDetermined else {
            return
        }

        let isGranted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { isGranted in
                continuation.resume(returning: isGranted)
            }
        }

        cameraAuthorizationStatus = isGranted ? .authorized : AVCaptureDevice.authorizationStatus(for: .video)
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(settingsURL)
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
