import Foundation
import CoreLocation
import CoreBluetooth

struct MissionLogEntry: Identifiable, Codable {
    enum EventType: String, Codable {
        case locationUpdate
        case scanStarted
        case scanStopped
        case deviceDiscovered
        case deviceUpdated
        case deviceConnected
        case deviceDisconnected
        case deviceServices
        case error
        case note
    }

    let id: UUID
    let timestamp: Date
    let type: EventType
    let message: String
    let metadata: [String: String]?

    init(type: EventType, message: String, metadata: [String: String]? = nil, id: UUID = UUID(), timestamp: Date = Date()) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.message = message
        self.metadata = metadata
    }
}

enum ScanMode: String, Codable, CaseIterable, Identifiable {
    case passive
    case active

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .passive:
            return "Passive Scan"
        case .active:
            return "Active Scan"
        }
    }

    var description: String {
        switch self {
        case .passive:
            return "Listens for nearby Bluetooth advertisements without initiating follow-up requests."
        case .active:
            return "Attempts connections after discovery to request device information and services."
        }
    }
}

struct BluetoothDevice: Identifiable, Hashable {
    enum ConnectionState: String, Codable {
        case idle
        case connecting
        case connected
        case failed
    }

    let id: UUID
    var name: String
    var lastRSSI: Int
    var lastSeen: Date
    var state: ConnectionState
    var services: [BluetoothServiceInfo]
    var manufacturerData: String?

    init(id: UUID, name: String?, rssi: Int, lastSeen: Date = Date(), state: ConnectionState = .idle, services: [BluetoothServiceInfo] = [], manufacturerData: String? = nil) {
        self.id = id
        self.name = name ?? "Unknown"
        self.lastRSSI = rssi
        self.lastSeen = lastSeen
        self.state = state
        self.services = services
        self.manufacturerData = manufacturerData
    }

    var signalDescription: String {
        "RSSI: \(lastRSSI) dBm"
    }
}

extension BluetoothDevice: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, lastRSSI, lastSeen, state, services, manufacturerData, signalDescription
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let lastRSSI = try container.decode(Int.self, forKey: .lastRSSI)
        let lastSeen = try container.decode(Date.self, forKey: .lastSeen)
        let state = try container.decode(ConnectionState.self, forKey: .state)
        let services = try container.decode([BluetoothServiceInfo].self, forKey: .services)
        let manufacturerData = try container.decodeIfPresent(String.self, forKey: .manufacturerData)
        self.init(id: id, name: name, rssi: lastRSSI, lastSeen: lastSeen, state: state, services: services, manufacturerData: manufacturerData)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(lastRSSI, forKey: .lastRSSI)
        try container.encode(lastSeen, forKey: .lastSeen)
        try container.encode(state, forKey: .state)
        try container.encode(services, forKey: .services)
        try container.encodeIfPresent(manufacturerData, forKey: .manufacturerData)
        try container.encode(signalDescription, forKey: .signalDescription)
    }
}

struct BluetoothServiceInfo: Identifiable, Hashable {
    let id: CBUUID
    var characteristics: [CBUUID]

    init(id: CBUUID, characteristics: [CBUUID] = []) {
        self.id = id
        self.characteristics = characteristics
    }
}

extension BluetoothServiceInfo: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case characteristics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let idString = try container.decode(String.self, forKey: .id)
        id = CBUUID(string: idString)
        let characteristicStrings = try container.decode([String].self, forKey: .characteristics)
        characteristics = characteristicStrings.map { CBUUID(string: $0) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(characteristics.map { $0.uuidString }, forKey: .characteristics)
    }
}

struct MissionState: Codable {
    var scanMode: ScanMode
    var isScanning: Bool
    var location: CLLocationCoordinate2D?
    var devices: [BluetoothDevice]
    var logEntries: [MissionLogEntry]

    init(scanMode: ScanMode, isScanning: Bool, location: CLLocationCoordinate2D?, devices: [BluetoothDevice], logEntries: [MissionLogEntry]) {
        self.scanMode = scanMode
        self.isScanning = isScanning
        self.location = location
        self.devices = devices
        self.logEntries = logEntries
    }

    private enum CodingKeys: String, CodingKey {
        case scanMode
        case isScanning
        case location
        case devices
        case logEntries
    }

    private enum LocationCodingKeys: String, CodingKey {
        case latitude
        case longitude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scanMode = try container.decode(ScanMode.self, forKey: .scanMode)
        isScanning = try container.decode(Bool.self, forKey: .isScanning)
        devices = try container.decode([BluetoothDevice].self, forKey: .devices)
        logEntries = try container.decode([MissionLogEntry].self, forKey: .logEntries)

        if container.contains(.location) {
            if try container.decodeNil(forKey: .location) {
                location = nil
            } else {
                let locationContainer = try container.nestedContainer(keyedBy: LocationCodingKeys.self, forKey: .location)
                let latitude = try locationContainer.decode(CLLocationDegrees.self, forKey: .latitude)
                let longitude = try locationContainer.decode(CLLocationDegrees.self, forKey: .longitude)
                location = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
        } else {
            location = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scanMode, forKey: .scanMode)
        try container.encode(isScanning, forKey: .isScanning)
        try container.encode(devices, forKey: .devices)
        try container.encode(logEntries, forKey: .logEntries)

        if let location {
            var locationContainer = container.nestedContainer(keyedBy: LocationCodingKeys.self, forKey: .location)
            try locationContainer.encode(location.latitude, forKey: .latitude)
            try locationContainer.encode(location.longitude, forKey: .longitude)
        } else {
            try container.encodeNil(forKey: .location)
        }
    }
}
