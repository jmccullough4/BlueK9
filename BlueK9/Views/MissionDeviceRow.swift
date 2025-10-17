import SwiftUI
import CoreBluetooth

struct MissionDeviceRow: View {
    let device: BluetoothDevice
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            signalIndicator
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                Text("Last seen \(dateFormatter.string(from: device.lastSeen))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let manufacturer = device.manufacturerData {
                    Text("Manufacturer: \(manufacturer)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !device.services.isEmpty {
                    Text("Services: \(device.services.map { $0.id.uuidString }.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            statusPill
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var signalIndicator: some View {
        VStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(signalColor)
            Text("\(device.lastRSSI) dBm")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(signalColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusPill: some View {
        Text(device.state.rawValue.capitalized)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.16))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var signalColor: Color {
        switch device.lastRSSI {
        case ..<(-80): return .red
        case -80..<(-60): return .orange
        case -60..<(-40): return .yellow
        default: return .green
        }
    }

    private var statusColor: Color {
        switch device.state {
        case .idle: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .failed: return .red
        }
    }
}

#Preview {
    MissionDeviceRow(device: BluetoothDevice(id: UUID(), name: "Responder Beacon", rssi: -48, state: .connected, services: [BluetoothServiceInfo(id: CBUUID(string: "180D"))], manufacturerData: "0A1B2C"))
        .padding()
        .previewLayout(.sizeThatFits)
}
