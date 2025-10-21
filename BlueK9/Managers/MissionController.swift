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

    private func startWebServer() {
        let server = WebControlServer(
            stateProvider: { [weak self] in
                guard let self else {
                    return MissionState(scanMode: .passive, isScanning: false, location: nil, devices: [], logEntries: [], coordinatePreference: .latitudeLongitude, targetDeviceID: nil)
                }
                return MissionState(scanMode: self.scanMode, isScanning: self.isScanning, location: self.location, devices: self.devices, logEntries: self.logEntries, coordinatePreference: self.coordinateDisplayMode, targetDeviceID: self.targetDeviceID)
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
        logManager.persist(entries: logEntries)
    }

    private func updateDevice(_ device: BluetoothDevice) {
        var enrichedDevice = device
        if let coordinate = location {
            var history = enrichedDevice.locations
            history.append(DeviceGeo(coordinate: coordinate))
            enrichedDevice.locations = history
        }

        let previousLocationCount = devices.first(where: { $0.id == enrichedDevice.id })?.locations.count ?? 0

        if let index = devices.firstIndex(where: { $0.id == enrichedDevice.id }) {
            var merged = devices[index]
            merged.name = enrichedDevice.name
            merged.lastRSSI = enrichedDevice.lastRSSI
            merged.lastSeen = enrichedDevice.lastSeen
            merged.state = enrichedDevice.state
            merged.services = enrichedDevice.services
            merged.manufacturerData = enrichedDevice.manufacturerData
            merged.hardwareAddress = enrichedDevice.hardwareAddress
            merged.advertisedServiceUUIDs = enrichedDevice.advertisedServiceUUIDs
            merged.estimatedRange = enrichedDevice.estimatedRange
            merged.mapColorHex = enrichedDevice.mapColorHex
            var locations = merged.locations
            locations.append(contentsOf: enrichedDevice.locations)
            var seen: Set<UUID> = []
            merged.locations = locations.filter { seen.insert($0.id).inserted }
            devices[index] = merged
        } else {
            devices.append(enrichedDevice)
        }

        devices.sort { $0.lastSeen > $1.lastSeen }

        if let idx = devices.firstIndex(where: { $0.id == enrichedDevice.id }) {
            if let latest = devices[idx].lastKnownLocation {
                let formatted = CoordinateFormatter.shared.string(from: latest.coordinate, mode: coordinateDisplayMode)
                devices[idx].displayCoordinate = formatted
                if devices[idx].locations.count > previousLocationCount {
                    appendLog(MissionLogEntry(type: .deviceUpdated, message: "Geo fix for \(devices[idx].name)", metadata: ["coordinate": formatted, "uuid": enrichedDevice.id.uuidString]))
                }
            } else {
                devices[idx].displayCoordinate = nil
            }
        }
    }

    private func bootstrapPreview() {
        location = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
        isScanning = true
        locationAuthorizationStatus = .authorizedAlways
        bluetoothState = .poweredOn
        devices = [
            BluetoothDevice(id: UUID(), name: "Responder Beacon", rssi: -42, state: .connected, estimatedRange: 2.0, locations: [DeviceGeo(coordinate: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090))], displayCoordinate: CoordinateFormatter.shared.string(from: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090), mode: coordinateDisplayMode)),
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
