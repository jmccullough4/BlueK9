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

    private let locationService: LocationService
    private let bluetoothService: BluetoothService
    private let logManager: LogManager
    private var webServer: WebControlServer?
    init(preview: Bool = false) {
        self.locationService = LocationService()
        self.bluetoothService = BluetoothService()
        self.logManager = LogManager()
        self.logEntries = logManager.load()
        self.locationAuthorizationStatus = locationService.authorizationStatus
        self.bluetoothState = bluetoothService.state

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
                    return MissionState(scanMode: .passive, isScanning: false, location: nil, devices: [], logEntries: [])
                }
                return MissionState(scanMode: self.scanMode, isScanning: self.isScanning, location: self.location, devices: self.devices, logEntries: self.logEntries)
            },
            commandHandler: { [weak self] command in
                Task { @MainActor in
                    switch command {
                    case .startScan(let mode):
                        self?.startScanning(mode: mode)
                    case .stopScan:
                        self?.stopScanning()
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
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
        devices.sort { $0.lastSeen > $1.lastSeen }
    }

    private func bootstrapPreview() {
        location = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
        isScanning = true
        locationAuthorizationStatus = .authorizedAlways
        bluetoothState = .poweredOn
        devices = [
            BluetoothDevice(id: UUID(), name: "Responder Beacon", rssi: -42, state: .connected),
            BluetoothDevice(id: UUID(), name: "Body Cam", rssi: -67, state: .idle)
        ]
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
