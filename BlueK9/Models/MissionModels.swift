import Foundation
import CoreLocation
import CoreBluetooth

struct DeviceGeo: Identifiable, Hashable, Codable {
    let id: UUID
    let timestamp: Date
    let coordinate: CLLocationCoordinate2D
    let accuracy: CLLocationAccuracy?

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         coordinate: CLLocationCoordinate2D,
         accuracy: CLLocationAccuracy? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.accuracy = accuracy
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case latitude
        case longitude
        case accuracy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        let latitude = try container.decode(CLLocationDegrees.self, forKey: .latitude)
        let longitude = try container.decode(CLLocationDegrees.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        accuracy = try container.decodeIfPresent(CLLocationAccuracy.self, forKey: .accuracy)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encodeIfPresent(accuracy, forKey: .accuracy)
    }
}

extension DeviceGeo {
    static func == (lhs: DeviceGeo, rhs: DeviceGeo) -> Bool {
        lhs.id == rhs.id &&
        lhs.timestamp == rhs.timestamp &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.accuracy == rhs.accuracy
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(timestamp)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(accuracy ?? -1)
    }
}

enum CoordinateDisplayMode: String, CaseIterable, Identifiable, Codable {
    case latitudeLongitude
    case mgrs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .latitudeLongitude:
            return "Lat/Lon"
        case .mgrs:
            return "MGRS"
        }
    }
}

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

struct MissionLogDescriptor: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
    var hardwareAddress: String
    var advertisedServiceUUIDs: [CBUUID]
    var estimatedRange: Double?
    var locations: [DeviceGeo]
    var displayCoordinate: String?
    var mapColorHex: String

    init(id: UUID,
         name: String?,
         rssi: Int,
         lastSeen: Date = Date(),
         state: ConnectionState = .idle,
         services: [BluetoothServiceInfo] = [],
         manufacturerData: String? = nil,
         hardwareAddress: String? = nil,
         advertisedServiceUUIDs: [CBUUID] = [],
         estimatedRange: Double? = nil,
         locations: [DeviceGeo] = [],
         displayCoordinate: String? = nil,
         mapColorHex: String? = nil) {
        self.id = id
        self.name = name ?? "Unknown"
        self.lastRSSI = rssi
        self.lastSeen = lastSeen
        self.state = state
        self.services = services
        self.manufacturerData = manufacturerData
        self.hardwareAddress = hardwareAddress ?? id.uuidString
        self.advertisedServiceUUIDs = advertisedServiceUUIDs
        self.estimatedRange = estimatedRange
        self.locations = locations
        self.displayCoordinate = displayCoordinate
        self.mapColorHex = mapColorHex ?? DeviceColorPalette.hexString(for: id)
    }

    var signalDescription: String {
        "RSSI: \(lastRSSI) dBm"
    }

    var lastKnownLocation: DeviceGeo? {
        locations.sorted(by: { $0.timestamp > $1.timestamp }).first
    }
}

extension BluetoothDevice: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, lastRSSI, lastSeen, state, services, manufacturerData, hardwareAddress, advertisedServiceUUIDs, estimatedRange, locations, displayCoordinate, signalDescription, mapColorHex
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
        let hardwareAddress = try container.decodeIfPresent(String.self, forKey: .hardwareAddress)
        let advertisedServiceUUIDs = try container.decodeIfPresent([String].self, forKey: .advertisedServiceUUIDs)?.map { CBUUID(string: $0) } ?? []
        let estimatedRange = try container.decodeIfPresent(Double.self, forKey: .estimatedRange)
        let locations = try container.decodeIfPresent([DeviceGeo].self, forKey: .locations) ?? []
        let displayCoordinate = try container.decodeIfPresent(String.self, forKey: .displayCoordinate)
        let mapColorHex = try container.decodeIfPresent(String.self, forKey: .mapColorHex)
        self.init(id: id, name: name, rssi: lastRSSI, lastSeen: lastSeen, state: state, services: services, manufacturerData: manufacturerData, hardwareAddress: hardwareAddress, advertisedServiceUUIDs: advertisedServiceUUIDs, estimatedRange: estimatedRange, locations: locations, displayCoordinate: displayCoordinate, mapColorHex: mapColorHex)
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
        try container.encode(hardwareAddress, forKey: .hardwareAddress)
        try container.encode(advertisedServiceUUIDs.map { $0.uuidString }, forKey: .advertisedServiceUUIDs)
        try container.encodeIfPresent(estimatedRange, forKey: .estimatedRange)
        if !locations.isEmpty {
            try container.encode(locations, forKey: .locations)
        }
        try container.encodeIfPresent(displayCoordinate, forKey: .displayCoordinate)
        try container.encode(signalDescription, forKey: .signalDescription)
        try container.encode(mapColorHex, forKey: .mapColorHex)
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
    var locationAccuracy: CLLocationAccuracy?
    var devices: [BluetoothDevice]
    var logEntries: [MissionLogEntry]
    var coordinatePreference: CoordinateDisplayMode
    var targetDeviceID: UUID?
    var logs: [MissionLogDescriptor]
    var activeLogID: UUID?

    static let empty = MissionState(
        scanMode: .passive,
        isScanning: false,
        location: nil,
        locationAccuracy: nil,
        devices: [],
        logEntries: [],
        coordinatePreference: .latitudeLongitude,
        targetDeviceID: nil
    )

    init(scanMode: ScanMode,
         isScanning: Bool,
         location: CLLocationCoordinate2D?,
         locationAccuracy: CLLocationAccuracy?,
         devices: [BluetoothDevice],
         logEntries: [MissionLogEntry],
         coordinatePreference: CoordinateDisplayMode,
         targetDeviceID: UUID?,
         logs: [MissionLogDescriptor] = [],
         activeLogID: UUID? = nil) {
        self.scanMode = scanMode
        self.isScanning = isScanning
        self.location = location
        self.locationAccuracy = locationAccuracy
        self.devices = devices
        self.logEntries = logEntries
        self.coordinatePreference = coordinatePreference
        self.targetDeviceID = targetDeviceID
        self.logs = logs
        self.activeLogID = activeLogID
    }

    private enum CodingKeys: String, CodingKey {
        case scanMode
        case isScanning
        case location
        case locationAccuracy
        case devices
        case logEntries
        case coordinatePreference
        case targetDeviceID
        case logs
        case activeLogID
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
        coordinatePreference = try container.decode(CoordinateDisplayMode.self, forKey: .coordinatePreference)
        targetDeviceID = try container.decodeIfPresent(UUID.self, forKey: .targetDeviceID)
        logs = try container.decodeIfPresent([MissionLogDescriptor].self, forKey: .logs) ?? []
        activeLogID = try container.decodeIfPresent(UUID.self, forKey: .activeLogID)
        locationAccuracy = try container.decodeIfPresent(CLLocationAccuracy.self, forKey: .locationAccuracy)

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
        try container.encode(coordinatePreference, forKey: .coordinatePreference)
        try container.encodeIfPresent(targetDeviceID, forKey: .targetDeviceID)
        try container.encode(logs, forKey: .logs)
        try container.encodeIfPresent(activeLogID, forKey: .activeLogID)
        try container.encodeIfPresent(locationAccuracy, forKey: .locationAccuracy)

        if let location {
            var locationContainer = container.nestedContainer(keyedBy: LocationCodingKeys.self, forKey: .location)
            try locationContainer.encode(location.latitude, forKey: .latitude)
            try locationContainer.encode(location.longitude, forKey: .longitude)
        } else {
            try container.encodeNil(forKey: .location)
        }
    }
}
