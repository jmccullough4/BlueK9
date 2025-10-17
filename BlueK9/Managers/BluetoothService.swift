import Foundation
import CoreBluetooth

protocol BluetoothServiceDelegate: AnyObject {
    func bluetoothService(_ service: BluetoothService, didChangeScanning isScanning: Bool, mode: ScanMode)
    func bluetoothService(_ service: BluetoothService, didDiscover device: BluetoothDevice)
    func bluetoothService(_ service: BluetoothService, didUpdate device: BluetoothDevice)
    func bluetoothService(_ service: BluetoothService, didLog entry: MissionLogEntry)
    func bluetoothService(_ service: BluetoothService, didUpdateState state: CBManagerState)
}

final class BluetoothService: NSObject {
    private let centralQueue = DispatchQueue(label: "com.bluek9.bluetooth", qos: .userInitiated)
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var devices: [UUID: BluetoothDevice] = [:]
    private var pendingScanMode: ScanMode?
    private(set) var isScanning: Bool = false
    weak var delegate: BluetoothServiceDelegate?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: centralQueue)
    }

    var state: CBManagerState {
        central.state
    }

    func startScanning(mode: ScanMode) {
        centralQueue.async { [weak self] in
            guard let self else { return }
            self.pendingScanMode = mode
            guard self.central.state == .poweredOn else { return }
            self.scan(with: mode)
        }
    }

    func stopScanning() {
        centralQueue.async { [weak self] in
            guard let self else { return }
            guard self.isScanning else { return }
            self.central.stopScan()
            self.isScanning = false
            self.delegate?.bluetoothService(self, didChangeScanning: false, mode: self.pendingScanMode ?? .passive)
            self.delegate?.bluetoothService(self, didLog: MissionLogEntry(type: .scanStopped, message: "Bluetooth scanning stopped"))
        }
    }

    private func scan(with mode: ScanMode) {
        if isScanning {
            central.stopScan()
        }
        let options: [String: Any] = [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        central.scanForPeripherals(withServices: nil, options: options)
        isScanning = true
        delegate?.bluetoothService(self, didChangeScanning: true, mode: mode)
        delegate?.bluetoothService(self, didLog: MissionLogEntry(type: .scanStarted, message: "Bluetooth \(mode.displayName.lowercased()) started"))
    }

    private func update(device newDevice: BluetoothDevice) {
        devices[newDevice.id] = newDevice
        delegate?.bluetoothService(self, didUpdate: newDevice)
    }

    private func buildDevice(from peripheral: CBPeripheral, rssi: NSNumber, advertisementData: [String: Any]) -> BluetoothDevice {
        let manufacturerData = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.map { String(format: "%02hhX", $0) }.joined()
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        var device = devices[peripheral.identifier] ?? BluetoothDevice(id: peripheral.identifier, name: name, rssi: rssi.intValue)
        device.name = name ?? device.name
        device.lastRSSI = rssi.intValue
        device.lastSeen = Date()
        device.manufacturerData = manufacturerData
        return device
    }
}

extension BluetoothService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if let mode = pendingScanMode {
                scan(with: mode)
            }
        case .unauthorized:
            delegate?.bluetoothService(self, didLog: MissionLogEntry(type: .error, message: "Bluetooth permission denied"))
        case .poweredOff:
            delegate?.bluetoothService(self, didLog: MissionLogEntry(type: .error, message: "Bluetooth is powered off"))
        default:
            break
        }

        delegate?.bluetoothService(self, didUpdateState: central.state)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let device = buildDevice(from: peripheral, rssi: RSSI, advertisementData: advertisementData)
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        devices[peripheral.identifier] = device
        delegate?.bluetoothService(self, didDiscover: device)
        delegate?.bluetoothService(self, didLog: MissionLogEntry(type: .deviceDiscovered, message: "Discovered \(device.name)", metadata: ["rssi": "\(device.lastRSSI)"]))

        guard let mode = pendingScanMode, mode == .active else {
            return
        }

        if peripheral.state == .disconnected {
            devices[peripheral.identifier]?.state = .connecting
            delegate?.bluetoothService(self, didUpdate: devices[peripheral.identifier]!)
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        var device = devices[peripheral.identifier] ?? BluetoothDevice(id: peripheral.identifier, name: peripheral.name, rssi: -100)
        device.state = .connected
        devices[peripheral.identifier] = device
        delegate?.bluetoothService(self, didUpdate: device)
        delegate?.bluetoothService(self, didLog: MissionLogEntry(type: .deviceConnected, message: "Connected to \(device.name)"))
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        var device = devices[peripheral.identifier] ?? BluetoothDevice(id: peripheral.identifier, name: peripheral.name, rssi: -100)
        device.state = .failed
        devices[peripheral.identifier] = device
        delegate?.bluetoothService(self, didUpdate: device)
        delegate?.bluetoothService(self, didLog: MissionLogEntry(type: .error, message: "Failed to connect to \(device.name)", metadata: ["error": error?.localizedDescription ?? "Unknown"]))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        var device = devices[peripheral.identifier] ?? BluetoothDevice(id: peripheral.identifier, name: peripheral.name, rssi: -100)
        device.state = .idle
        devices[peripheral.identifier] = device
        delegate?.bluetoothService(self, didUpdate: device)
        delegate?.bluetoothService(self, didLog: MissionLogEntry(type: .deviceDisconnected, message: "Disconnected from \(device.name)"))
    }
}

extension BluetoothService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            delegate?.bluetoothService(self, didLog: MissionLogEntry(type: .error, message: "Service discovery failed", metadata: ["error": error.localizedDescription]))
            return
        }

        guard let services = peripheral.services else { return }
        var device = devices[peripheral.identifier] ?? BluetoothDevice(id: peripheral.identifier, name: peripheral.name, rssi: -100)
        device.services = services.map { BluetoothServiceInfo(id: $0.uuid) }
        devices[peripheral.identifier] = device
        delegate?.bluetoothService(self, didUpdate: device)
        delegate?.bluetoothService(self, didLog: MissionLogEntry(type: .deviceServices, message: "Discovered services for \(device.name)"))

        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            delegate?.bluetoothService(self, didLog: MissionLogEntry(type: .error, message: "Characteristic discovery failed", metadata: ["error": error.localizedDescription]))
            return
        }

        guard let characteristics = service.characteristics else { return }
        var device = devices[peripheral.identifier]
        if var info = device?.services.first(where: { $0.id == service.uuid }) {
            info.characteristics = characteristics.map { $0.uuid }
            if let index = device?.services.firstIndex(where: { $0.id == service.uuid }) {
                device?.services[index] = info
            }
        }
        if let updated = device {
            devices[peripheral.identifier] = updated
            delegate?.bluetoothService(self, didUpdate: updated)
        }
    }
}
