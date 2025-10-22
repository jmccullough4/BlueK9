import Foundation
import CoreLocation
import CoreBluetooth

@MainActor
final class MissionController: ObservableObject {
    @Published var devices: [BluetoothDevice] = []
    @Published var logEntries: [MissionLogEntry]
    @Published var logs: [MissionLogDescriptor]
    @Published var activeLog: MissionLogDescriptor
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
    private let customNamesKey = "MissionCustomDeviceNames"
    private let locationHistoryLimit = 120
    private let logHistoryLimit = 1000
    private let webLogLimit = 200
    private let webLocationHistoryLimit = 60
    private let staleDeviceInterval: TimeInterval = 15 * 60
    private let pruneCheckInterval: TimeInterval = 60
    private var lastPruneCheck = Date.distantPast
    private var customDeviceNames: [UUID: String]
    init(preview: Bool = false) {
        self.locationService = LocationService()
        self.bluetoothService = BluetoothService()
        self.logManager = LogManager()
        let logSnapshot = logManager.bootstrap()
        self.logEntries = logSnapshot.entries
        self.logs = logSnapshot.logs
        self.activeLog = logSnapshot.activeLog
        self.locationAuthorizationStatus = locationService.currentAuthorizationStatus
        self.bluetoothState = bluetoothService.state
        if let stored = UserDefaults.standard.string(forKey: coordinatePreferenceKey), let mode = CoordinateDisplayMode(rawValue: stored) {
            self.coordinateDisplayMode = mode
        } else {
            self.coordinateDisplayMode = .latitudeLongitude
        }
        self.targetDeviceID = nil
        if let storedNames = UserDefaults.standard.dictionary(forKey: customNamesKey) as? [String: String] {
            self.customDeviceNames = storedNames.reduce(into: [:]) { partialResult, element in
                if let uuid = UUID(uuidString: element.key) {
                    partialResult[uuid] = element.value
                }
            }
        } else {
            self.customDeviceNames = [:]
        }

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
        logManager.exportCSV()
    }

    func selectLog(_ descriptor: MissionLogDescriptor) {
        selectLog(id: descriptor.id)
    }

    func selectLog(id: UUID) {
        let snapshot = logManager.selectLog(id: id)
        replaceLogState(with: snapshot)
        appendLog(MissionLogEntry(type: .note, message: "Switched to log", metadata: ["name": snapshot.activeLog.name]))
    }

    func createLog(named name: String) {
        let snapshot = logManager.createLog(named: name)
        replaceLogState(with: snapshot)
        appendLog(MissionLogEntry(type: .note, message: "Log created", metadata: ["name": snapshot.activeLog.name]))
    }

    func renameActiveLog(to name: String) {
        renameLog(id: activeLog.id, to: name, shouldLog: true)
    }

    func renameLog(id: UUID, to name: String) {
        renameLog(id: id, to: name, shouldLog: activeLog.id == id)
    }

    func deleteLog(_ descriptor: MissionLogDescriptor) {
        deleteLog(id: descriptor.id, name: descriptor.name)
    }

    func deleteLog(id: UUID, name: String? = nil) {
        let snapshot = logManager.deleteLog(id: id)
        replaceLogState(with: snapshot)
        if let name = name, !name.isEmpty {
            appendLog(MissionLogEntry(type: .note, message: "Log deleted", metadata: ["name": name]))
        } else {
            appendLog(MissionLogEntry(type: .note, message: "Log deleted"))
        }
    }

    func deleteAllLogs() {
        let snapshot = logManager.deleteAllLogs()
        replaceLogState(with: snapshot)
        appendLog(MissionLogEntry(type: .note, message: "Logs reset"))
    }

    func clearDevices() {
        devices.removeAll()
        targetDeviceID = nil
        appendLog(MissionLogEntry(type: .note, message: "Device list cleared"))
    }

    func renameDevice(_ device: BluetoothDevice, to name: String) {
        setCustomName(name, for: device.id)
    }

    func clearDeviceName(_ device: BluetoothDevice) {
        setCustomName(nil, for: device.id)
    }

    func renameDevice(id: UUID, to name: String) {
        setCustomName(name, for: id)
    }

    func clearDeviceName(id: UUID) {
        setCustomName(nil, for: id)
    }

    func hasCustomName(for id: UUID) -> Bool {
        if let value = customDeviceNames[id] {
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    @MainActor
    private func makeWebMissionState() -> MissionState {
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
            targetDeviceID: targetDeviceID,
            logs: logs,
            activeLogID: activeLog.id
        )
    }

    private func makeEmptyMissionState() -> MissionState {
        MissionState.empty
    }

    private func startWebServer() {
        let server = WebControlServer(
            stateProvider: { [weak self] in
                guard let self else {
                    return MissionState.empty
                }

                if Thread.isMainThread {
                    return self.makeWebMissionState()
                }

                var snapshot: MissionState?
                DispatchQueue.main.sync {
                    snapshot = self.makeWebMissionState()
                }
                return snapshot ?? self.makeEmptyMissionState()
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
                    case .createLog(let name):
                        self?.createLog(named: name)
                    case .selectLog(let id):
                        self?.selectLog(id: id)
                    case .renameLog(let id, let name):
                        self?.renameLog(id: id, to: name)
                    case .deleteLog(let id, let name):
                        self?.deleteLog(id: id, name: name)
                    case .deleteAllLogs:
                        self?.deleteAllLogs()
                    case .clearDevices:
                        self?.clearDevices()
                    case .setCustomName(let id, let name):
                        if let name {
                            self?.renameDevice(id: id, to: name)
                        } else {
                            self?.clearDeviceName(id: id)
                        }
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
        let snapshot = logManager.persist(entries: logEntries)
        updateLogMetadata(from: snapshot)
    }

    private func replaceLogState(with snapshot: LogSnapshot) {
        logEntries = snapshot.entries
        updateLogMetadata(from: snapshot)
    }

    private func updateLogMetadata(from snapshot: LogSnapshot) {
        logs = snapshot.logs
        activeLog = snapshot.activeLog
    }

    private func renameLog(id: UUID, to name: String, shouldLog: Bool) {
        let snapshot = logManager.renameLog(id: id, to: name)
        replaceLogState(with: snapshot)
        if shouldLog, snapshot.activeLog.id == id {
            appendLog(MissionLogEntry(type: .note, message: "Log renamed", metadata: ["name": snapshot.activeLog.name]))
        }
    }

    private func setCustomName(_ rawName: String?, for id: UUID) {
        let trimmed = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            guard customDeviceNames.removeValue(forKey: id) != nil else { return }
            persistCustomNames()
            updateDevicesForCustomNames()
            appendLog(MissionLogEntry(type: .note, message: "Cleared device alias", metadata: ["uuid": id.uuidString]))
            return
        }

        guard customDeviceNames[id] != trimmed else { return }
        customDeviceNames[id] = trimmed
        persistCustomNames()
        updateDevicesForCustomNames()
        appendLog(MissionLogEntry(type: .note, message: "Named device", metadata: ["uuid": id.uuidString, "name": trimmed]))
    }

    private func persistCustomNames() {
        let stored = customDeviceNames.reduce(into: [String: String]()) { partialResult, element in
            partialResult[element.key.uuidString] = element.value
        }
        UserDefaults.standard.set(stored, forKey: customNamesKey)
    }

    private func updateDevicesForCustomNames() {
        devices = devices.map { device in
            var updated = device
            applyCustomName(&updated)
            return updated
        }
    }

    private func applyCustomName(_ device: inout BluetoothDevice) {
        if let custom = customDeviceNames[device.id], !custom.isEmpty {
            device.name = custom
        }
    }

    private func updateDevice(_ device: BluetoothDevice) {
        let previousLocationCount = devices.first(where: { $0.id == device.id })?.locations.count ?? 0
        let mergeResult = merge(device)
        var updatedDevice = mergeResult.device
        var appendedNewLocation = mergeResult.appendedLocation

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
        applyCustomName(&existing)
        return (existing, appended)
    }

    private func sanitized(device: BluetoothDevice) -> (device: BluetoothDevice, appendedLocation: Bool) {
        var cleaned = device
        cleaned.locations = []
        let appended = append(locations: device.locations, to: &cleaned.locations)
        applyCustomName(&cleaned)
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
            self.scanMode = mode
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
