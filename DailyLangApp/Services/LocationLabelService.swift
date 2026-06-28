import CoreLocation
import Foundation

@MainActor
final class LocationLabelService: NSObject, CLLocationManagerDelegate {
    private static let roadSpeedThresholdMetersPerSecond = 1.4
    private static let requestTimeoutNanoseconds: UInt64 = 8_000_000_000

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationLabel, Never>?
    private var fallbackLabel: LocationLabel = .unknown
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestAuthorizationIfNeeded() {
        guard manager.authorizationStatus == .notDetermined else {
            return
        }

        manager.requestWhenInUseAuthorization()
    }

    func currentLabel(fallback: LocationLabel) async -> LocationLabel {
        fallbackLabel = fallback

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            return fallback
        case .restricted, .denied:
            return fallback
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            return fallback
        }

        guard CLLocationManager.locationServicesEnabled() else {
            return fallback
        }

        finish(with: fallback)

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: Self.requestTimeoutNanoseconds)
                self?.finish(with: fallback)
            }
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let speed = locations.last?.speed
        Task { @MainActor in
            let label: LocationLabel
            if let speed, speed >= Self.roadSpeedThresholdMetersPerSecond {
                label = .road
            } else {
                label = fallbackLabel
            }
            finish(with: label)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            finish(with: fallbackLabel)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .denied || status == .restricted {
                finish(with: fallbackLabel)
            }
        }
    }

    private func finish(with label: LocationLabel) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: label)
        continuation = nil
    }

}
