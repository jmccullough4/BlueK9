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

    private let locationService: LocationService
    private let bluetoothService: BluetoothService
    private let logManager: LogManager
    private var webServer: WebControlServer?
    init(preview: Bool = false) {
        self.locationService = LocationService()
        self.bluetoothService = BluetoothService()
        self.logManager = LogManager()
        self.logEntries = logManager.load()

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
        startWebServer()
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
}
