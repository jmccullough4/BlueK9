import Foundation
import CoreLocation
import CoreBluetooth

@MainActor
final class MissionController: ObservableObject {
    @Published var devices: [BluetoothDevice] = []
    @Published var logEntries: [MissionLogEntry]
    @Published var isScanning: Bool = false
    @Published var scanMode: ScanMode = .passive
    @Published var location: CLLocationCoordinate2D?
    @Published var locationAccuracy: CLLocationAccuracy?
    @Published var locationAuthorizationStatus: CLAuthorizationStatus
    @Published var bluetoothState: CBManagerState
    @Published var targetDeviceID: UUID?
    @Published var coordinateDisplayMode: CoordinateDisplayMode

    private let locationService: LocationService
    private let bluetoothService: BluetoothService
    private let logManager: LogManager
    private var webServer: WebControlServer?
    private let coordinatePreferenceKey = "MissionCoordinateDisplayMode"
    private let locationHistoryLimit = 120
    private let logHistoryLimit = 1000
    private let webLogLimit = 200
    private let webLocationHistoryLimit = 60
    private let minimumCoordinateDelta = 0.00002
    private let staleDeviceInterval: TimeInterval = 15 * 60
    private let pruneCheckInterval: TimeInterval = 60
    private var lastPruneCheck = Date.distantPast
    init(preview: Bool = false) {
        self.locationService = LocationService()
        self.bluetoothService = BluetoothService()
        self.logManager = LogManager()
        self.logEntries = logManager.load()
        self.locationAuthorizationStatus = locationService.currentAuthorizationStatus
        self.bluetoothState = bluetoothService.state
        if let stored = UserDefaults.standard.string(forKey: coordinatePreferenceKey), let mode = CoordinateDisplayMode(rawValue: stored) {
            self.coordinateDisplayMode = mode
        } else {
            self.coordinateDisplayMode = .latitudeLongitude
        }
        self.targetDeviceID = nil

        locationService.delegate = self
        bluetoothService.delegate = self

        if preview {
            bootstrapPreview()
        } else {
            startServices()
        }
    }

    func startServices() {
        locationService.start()
        if webServer == nil {
            startWebServer()
        }
    }

    func requestLocationAuthorization() {
        locationService.requestAuthorization()
    }

    func engageMissionSystems() {
        startServices()
        startScanning(mode: scanMode)
    }

    func startScanning(mode: ScanMode? = nil) {
        let desiredMode = mode ?? scanMode
        scanMode = desiredMode
        bluetoothService.startScanning(mode: desiredMode)
    }

    func stopScanning() {
        bluetoothService.stopScanning()
    }

    func setCoordinateDisplayMode(_ mode: CoordinateDisplayMode) {
        guard coordinateDisplayMode != mode else { return }
        coordinateDisplayMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: coordinatePreferenceKey)
        devices = devices.map { device in
            var updated = device
            if let latest = device.lastKnownLocation {
                updated.displayCoordinate = CoordinateFormatter.shared.string(from: latest.coordinate, mode: mode)
            } else {
                updated.displayCoordinate = nil
            }
            return updated
        }
        appendLog(MissionLogEntry(type: .note, message: "Coordinate display updated", metadata: ["mode": mode.rawValue]))
    }

    func setTarget(_ device: BluetoothDevice) {
        targetDeviceID = device.id
        appendLog(MissionLogEntry(type: .note, message: "Target locked", metadata: ["device": device.name, "uuid": device.id.uuidString]))
    }

    func clearTarget() {
        guard let target = targetDeviceID else { return }
        targetDeviceID = nil
        appendLog(MissionLogEntry(type: .note, message: "Target cleared", metadata: ["uuid": target.uuidString]))
    }

    func performActiveGeo(on deviceID: UUID? = nil) {
        guard let targetID = deviceID ?? targetDeviceID else { return }
        bluetoothService.performActiveGeo(on: targetID)
    }

    func requestDeviceInfo(for deviceID: UUID? = nil) {
        guard let targetID = deviceID ?? targetDeviceID else { return }
        bluetoothService.requestDetailedInformation(for: targetID)
    }

    func logManual(_ message: String) {
        appendLog(MissionLogEntry(type: .note, message: message))
    }

    func logFileURL() -> URL {
        logManager.logURL()
    }

    @MainActor
    private func makeMissionStateSnapshot() -> MissionState {
        let trimmedDevices = devices.map { device -> BluetoothDevice in
            var copy = device
            if copy.locations.count > webLocationHistoryLimit {
                copy.locations = Array(copy.locations.suffix(webLocationHistoryLimit))
            }
            return copy
        }

        let limitedLog = Array(logEntries.suffix(webLogLimit))

        return MissionState(
            scanMode: scanMode,
            isScanning: isScanning,
            location: location,
            locationAccuracy: locationAccuracy,
            devices: trimmedDevices,
            logEntries: limitedLog,
            coordinatePreference: coordinateDisplayMode,
            targetDeviceID: targetDeviceID
        )
    }

    private func emptyMissionState() -> MissionState {
        MissionState(
            scanMode: .passive,
            isScanning: false,
            location: nil,
            locationAccuracy: nil,
            devices: [],
            logEntries: [],
            coordinatePreference: .latitudeLongitude,
            targetDeviceID: nil
        )
    }

    private func startWebServer() {
        let server = WebControlServer(
            stateProvider: { [weak self] in
                guard let self else {
                    return MissionState(scanMode: .passive, isScanning: false, location: nil, locationAccuracy: nil, devices: [], logEntries: [], coordinatePreference: .latitudeLongitude, targetDeviceID: nil)
                }

                if Thread.isMainThread {
                    return self.makeMissionStateSnapshot()
                }

                var snapshot: MissionState?
                DispatchQueue.main.sync {
                    snapshot = self.makeMissionStateSnapshot()
                }
                return snapshot ?? self.emptyMissionState()
            },
            commandHandler: { [weak self] command in
                Task { @MainActor in
                    switch command {
                    case .startScan(let mode):
                        self?.startScanning(mode: mode)
                    case .stopScan:
                        self?.stopScanning()
                    case .setTarget(let id):
                        if let device = self?.devices.first(where: { $0.id == id }) {
                            self?.setTarget(device)
                        }
                    case .clearTarget:
                        self?.clearTarget()
                    case .activeGeo(let id):
                        self?.performActiveGeo(on: id)
                    case .getInfo(let id):
                        self?.requestDeviceInfo(for: id)
                    case .setCoordinatePreference(let mode):
                        self?.setCoordinateDisplayMode(mode)
                    }
                }
            },
            logURLProvider: { [weak self] in
                self?.logFileURL() ?? FileManager.default.temporaryDirectory
            }
        )
        webServer = server
        server.start()
    }

    private func appendLog(_ entry: MissionLogEntry) {
        logEntries.append(entry)
        if logEntries.count > logHistoryLimit {
            logEntries.removeFirst(logEntries.count - logHistoryLimit)
        }
        logManager.persist(entries: logEntries)
    }

    private func updateDevice(_ device: BluetoothDevice) {
        let previousLocationCount = devices.first(where: { $0.id == device.id })?.locations.count ?? 0
        let mergeResult = merge(device)
        var updatedDevice = mergeResult.device
        var appendedNewLocation = mergeResult.appendedLocation

        if let coordinate = location {
            var history = updatedDevice.locations
            let latest = history.last
            if shouldRecord(coordinate: coordinate, comparedTo: latest) {
                history.append(DeviceGeo(coordinate: coordinate, accuracy: locationAccuracy))
                updatedDevice.locations = history
                appendedNewLocation = true
            }
        }

        trimHistory(for: &updatedDevice)

        if let index = devices.firstIndex(where: { $0.id == updatedDevice.id }) {
            devices[index] = updatedDevice
        } else {
            devices.append(updatedDevice)
        }

        devices.sort { $0.lastSeen > $1.lastSeen }

        pruneStaleDevicesIfNeeded(now: Date())

        if let idx = devices.firstIndex(where: { $0.id == updatedDevice.id }) {
            if let latest = devices[idx].lastKnownLocation {
                let formatted = CoordinateFormatter.shared.string(from: latest.coordinate, mode: coordinateDisplayMode)
                devices[idx].displayCoordinate = formatted
                if appendedNewLocation || devices[idx].locations.count > previousLocationCount {
                    appendLog(MissionLogEntry(type: .deviceUpdated, message: "Geo fix for \(devices[idx].name)", metadata: ["coordinate": formatted, "uuid": updatedDevice.id.uuidString]))
                }
            } else {
                devices[idx].displayCoordinate = nil
            }
        }
    }

    private func merge(_ incoming: BluetoothDevice) -> (device: BluetoothDevice, appendedLocation: Bool) {
        guard let index = devices.firstIndex(where: { $0.id == incoming.id }) else {
            return sanitized(device: incoming)
        }

        var existing = devices[index]
        existing.name = incoming.name
        existing.lastRSSI = incoming.lastRSSI
        existing.lastSeen = incoming.lastSeen
        existing.state = incoming.state
        existing.services = incoming.services
        existing.manufacturerData = incoming.manufacturerData
        existing.hardwareAddress = incoming.hardwareAddress
        existing.advertisedServiceUUIDs = incoming.advertisedServiceUUIDs
        existing.estimatedRange = incoming.estimatedRange
        existing.mapColorHex = incoming.mapColorHex
        let appended = append(locations: incoming.locations, to: &existing.locations)
        return (existing, appended)
    }

    private func sanitized(device: BluetoothDevice) -> (device: BluetoothDevice, appendedLocation: Bool) {
        var cleaned = device
        cleaned.locations = []
        let appended = append(locations: device.locations, to: &cleaned.locations)
        return (cleaned, appended)
    }

    private func append(locations newLocations: [DeviceGeo], to collection: inout [DeviceGeo]) -> Bool {
        guard !newLocations.isEmpty else { return false }
        var existingIDs = Set(collection.map { $0.id })
        var appended = false
        for location in newLocations {
            if existingIDs.insert(location.id).inserted {
                collection.append(location)
                appended = true
            }
        }
        return appended
    }

    private func shouldRecord(coordinate: CLLocationCoordinate2D, comparedTo previous: DeviceGeo?) -> Bool {
        guard let previous else { return true }
        let deltaLat = abs(previous.coordinate.latitude - coordinate.latitude)
        let deltaLon = abs(previous.coordinate.longitude - coordinate.longitude)
        return deltaLat > minimumCoordinateDelta || deltaLon > minimumCoordinateDelta
    }

    private func trimHistory(for device: inout BluetoothDevice) {
        if device.locations.count > locationHistoryLimit {
            device.locations = Array(device.locations.suffix(locationHistoryLimit))
        }
    }

    private func pruneStaleDevicesIfNeeded(now: Date) {
        guard now.timeIntervalSince(lastPruneCheck) >= pruneCheckInterval else { return }
        lastPruneCheck = now

        let cutoff = now.addingTimeInterval(-staleDeviceInterval)
        let staleDevices = devices.filter { device in
            guard device.id != targetDeviceID else { return false }
            return device.lastSeen < cutoff
        }

        guard !staleDevices.isEmpty else { return }

        let namesPreview = staleDevices.prefix(3).map { $0.name }.joined(separator: ", ")
        devices.removeAll { device in
            guard device.id != targetDeviceID else { return false }
            return device.lastSeen < cutoff
        }

        var metadata: [String: String] = ["count": "\(staleDevices.count)"]
        if !namesPreview.isEmpty {
            metadata["devices"] = namesPreview
        }
        appendLog(MissionLogEntry(type: .note, message: "Pruned stale devices", metadata: metadata))
    }

    private func bootstrapPreview() {
        location = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
        isScanning = true
        locationAuthorizationStatus = .authorizedAlways
        bluetoothState = .poweredOn
        devices = [
            BluetoothDevice(id: UUID(), name: "Responder Beacon", rssi: -42, state: .connected, estimatedRange: 2.0, locations: [DeviceGeo(coordinate: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090), accuracy: 4.0)], displayCoordinate: CoordinateFormatter.shared.string(from: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090), mode: coordinateDisplayMode)),
            BluetoothDevice(id: UUID(), name: "Body Cam", rssi: -67, state: .idle, estimatedRange: 6.5)
        ]
        targetDeviceID = devices.first?.id
        logEntries = [
            MissionLogEntry(type: .scanStarted, message: "Preview scanning engaged"),
            MissionLogEntry(type: .deviceDiscovered, message: "Responder Beacon", metadata: ["rssi": "-42"])
        ]
    }
}

extension MissionController: LocationServiceDelegate {
    nonisolated func locationService(_ service: LocationService, didUpdateLocation location: CLLocation) {
        Task { @MainActor in
            self.location = location.coordinate
            self.locationAccuracy = location.horizontalAccuracy
            appendLog(MissionLogEntry(type: .locationUpdate, message: "Location update", metadata: ["lat": "\(location.coordinate.latitude)", "lon": "\(location.coordinate.longitude)"] ))
            pruneStaleDevicesIfNeeded(now: Date())
        }
    }

    nonisolated func locationService(_ service: LocationService, didFailWith error: Error) {
        Task { @MainActor in
            appendLog(MissionLogEntry(type: .error, message: "Location error", metadata: ["error": error.localizedDescription]))
        }
    }

    nonisolated func locationService(_ service: LocationService, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.locationAuthorizationStatus = status
            switch status {
            case .authorizedAlways:
                appendLog(MissionLogEntry(type: .note, message: "Location access granted for always on tracking"))
            case .authorizedWhenInUse:
                appendLog(MissionLogEntry(type: .note, message: "Location access granted while in use"))
            case .denied, .restricted:
                appendLog(MissionLogEntry(type: .error, message: "Location permission denied"))
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
}

extension MissionController: BluetoothServiceDelegate {
    nonisolated func bluetoothService(_ service: BluetoothService, didChangeScanning isScanning: Bool, mode: ScanMode) {
        Task { @MainActor in
            self.isScanning = isScanning
        }
    }

    nonisolated func bluetoothService(_ service: BluetoothService, didDiscover device: BluetoothDevice) {
        Task { @MainActor in
            updateDevice(device)
        }
    }

    nonisolated func bluetoothService(_ service: BluetoothService, didUpdate device: BluetoothDevice) {
        Task { @MainActor in
            updateDevice(device)
        }
    }

    nonisolated func bluetoothService(_ service: BluetoothService, didLog entry: MissionLogEntry) {
        Task { @MainActor in
            appendLog(entry)
        }
    }

    nonisolated func bluetoothService(_ service: BluetoothService, didUpdateState state: CBManagerState) {
        Task { @MainActor in
            self.bluetoothState = state
            switch state {
            case .poweredOn:
                appendLog(MissionLogEntry(type: .note, message: "Bluetooth radio powered on"))
            case .poweredOff:
                appendLog(MissionLogEntry(type: .error, message: "Bluetooth radio powered off"))
            case .unauthorized:
                appendLog(MissionLogEntry(type: .error, message: "Bluetooth permission denied"))
            default:
                break
            }
        }
    }
}
