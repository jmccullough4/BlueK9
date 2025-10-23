import Foundation
import CoreBluetooth

enum BluetoothServiceCatalog {
    private static let standardAssignedNames: [String: String] = [
        "1800": "Generic Access",
        "1801": "Generic Attribute",
        "1802": "Immediate Alert",
        "1803": "Link Loss",
        "1804": "Tx Power",
        "1805": "Current Time",
        "180A": "Device Information",
        "180D": "Heart Rate",
        "180F": "Battery",
        "1811": "Alert Notification",
        "1812": "Human Interface Device",
        "1813": "Scan Parameters",
        "1814": "Running Speed & Cadence",
        "1815": "Automation IO",
        "1816": "Cycling Speed & Cadence",
        "1818": "Cycling Power",
        "181C": "User Data",
        "181E": "Bond Management",
        "1820": "Internet Protocol Support",
        "1821": "Indoor Positioning",
        "1822": "Pulse Oximeter",
        "1824": "Transport Discovery",
        "1826": "Fitness Machine",
        "1827": "Mesh Provisioning",
        "1828": "Mesh Proxy"
    ]

    private static let vendorSpecificNames: [String: String] = [
        "D0611E78-BBB4-4591-A5F8-487910AE4366": "Nearby Interaction",
        "9FA480E0-4967-4542-9390-D343DC5D04AE": "Apple Notification Center",
        "7DAF34AA-3E58-4B2D-8F9E-86A9A2265DC8": "Apple Continuity",
        "AF0BADB1-5B99-43CD-917A-A77BC549E3CC": "Exposure Notification",
        "00000000-0000-1000-8000-00805F9B34FB": "Bluetooth Base UUID"
    ]

    static func displayName(for uuid: CBUUID) -> String {
        let short = shortIdentifier(for: uuid)
        let baseName = assignedName(for: uuid.uuidString) ?? short
        if baseName == short {
            return baseName
        }
        return "\(baseName) (\(short))"
    }

    static func assignedName(for uuidString: String) -> String? {
        let canonical = uuidString.uppercased()
        if let name = vendorSpecificNames[canonical] {
            return name
        }
        let trimmed = canonical.replacingOccurrences(of: "-", with: "")
        if trimmed.count == 32 {
            let start = trimmed.index(trimmed.startIndex, offsetBy: 4)
            let end = trimmed.index(start, offsetBy: 4)
            let shortKey = String(trimmed[start..<end])
            if let name = standardAssignedNames[shortKey] {
                return name
            }
        }
        if trimmed.count == 4, let name = standardAssignedNames[trimmed] {
            return name
        }
        return nil
    }

    static func shortIdentifier(for uuid: CBUUID) -> String {
        let data = uuid.data
        if data.count == 2 {
            let value = data.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            return String(format: "0x%04X", value)
        } else if data.count == 4 {
            let value = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            return String(format: "0x%08X", value)
        }
        return uuid.uuidString.uppercased()
    }
}

extension BluetoothServiceInfo {
    var displayDescription: String {
        BluetoothServiceCatalog.displayName(for: id)
    }
}

extension Array where Element == CBUUID {
    func displayDescriptions() -> [String] {
        map { BluetoothServiceCatalog.displayName(for: $0) }
    }
}
