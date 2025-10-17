import Foundation
import CoreLocation

protocol LocationServiceDelegate: AnyObject {
    func locationService(_ service: LocationService, didUpdateLocation location: CLLocation)
    func locationService(_ service: LocationService, didFailWith error: Error)
    func locationService(_ service: LocationService, didChangeAuthorization status: CLAuthorizationStatus)
}

final class LocationService: NSObject {
    weak var delegate: LocationServiceDelegate?
    private let manager: CLLocationManager
    private var hasRequestedAlwaysAuthorization = false
    private static var supportsBackgroundLocationUpdates: Bool {
        guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            return false
        }
        return modes.contains("location")
    }

    private static var supportsAlwaysAuthorization: Bool {
        guard supportsBackgroundLocationUpdates else { return false }
        return Bundle.main.object(forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription") != nil
    }

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.pausesLocationUpdatesAutomatically = false
        if Self.supportsBackgroundLocationUpdates {
            manager.allowsBackgroundLocationUpdates = true
        }
    }

    var currentAuthorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func start() {
        evaluateAuthorization(shouldRequestPermission: true)
    }

    func requestAuthorization() {
        evaluateAuthorization(shouldRequestPermission: true, forceAlwaysRequest: true)
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    private func evaluateAuthorization(shouldRequestPermission: Bool, forceAlwaysRequest: Bool = false) {
        let status = manager.authorizationStatus

        switch status {
        case .authorizedAlways:
            hasRequestedAlwaysAuthorization = true
            manager.startUpdatingLocation()
        case .authorizedWhenInUse:
            manager.startUpdatingLocation()
            if shouldRequestPermission {
                requestAlwaysAuthorizationIfNeeded(force: forceAlwaysRequest)
            }
        case .notDetermined:
            hasRequestedAlwaysAuthorization = false
            if shouldRequestPermission {
                manager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            delegate?.locationService(self, didFailWith: LocationServiceError.permissionDenied)
        @unknown default:
            if shouldRequestPermission {
                manager.requestWhenInUseAuthorization()
            }
        }

        delegate?.locationService(self, didChangeAuthorization: status)
    }

    private func requestAlwaysAuthorizationIfNeeded(force: Bool = false) {
        if force {
            hasRequestedAlwaysAuthorization = false
        }
        guard !hasRequestedAlwaysAuthorization else { return }
        guard Self.supportsAlwaysAuthorization else {
            hasRequestedAlwaysAuthorization = true
            delegate?.locationService(self, didFailWith: LocationServiceError.alwaysAuthorizationUnavailable)
            return
        }
        hasRequestedAlwaysAuthorization = true
        manager.requestAlwaysAuthorization()
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        let shouldRequestAlways = status == .authorizedWhenInUse && !hasRequestedAlwaysAuthorization
        evaluateAuthorization(shouldRequestPermission: shouldRequestAlways)

        if status == .authorizedAlways || status == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        } else if status == .denied || status == .restricted {
            delegate?.locationService(self, didFailWith: LocationServiceError.permissionDenied)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        delegate?.locationService(self, didUpdateLocation: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        delegate?.locationService(self, didFailWith: error)
    }
}

enum LocationServiceError: LocalizedError {
    case permissionDenied
    case alwaysAuthorizationUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission denied. Please enable location access in Settings."
        case .alwaysAuthorizationUnavailable:
            return "App configuration does not allow requesting always-on location."
        }
    }
}
