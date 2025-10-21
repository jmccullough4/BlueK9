import SwiftUI
import CoreBluetooth
import CoreLocation

struct MissionDeviceRow: View {
    let device: BluetoothDevice
    let coordinateMode: CoordinateDisplayMode
    let isTarget: Bool
    let onMarkTarget: () -> Void
    let onClearTarget: () -> Void
    let onActiveGeo: () -> Void
    let onGetInfo: () -> Void

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            signalIndicator
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(device.name)
                        .font(.headline)
                    if isTarget {
                        Label("Target", systemImage: "scope")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.25))
                            .clipShape(Capsule())
                    }
                }

                Text("Last seen \(dateFormatter.string(from: device.lastSeen))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Address: \(device.hardwareAddress)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("UUID: \(device.id.uuidString)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let manufacturer = device.manufacturerData {
                    Text("Manufacturer: \(manufacturer)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !device.advertisedServiceUUIDs.isEmpty {
                    Text("Advertised UUIDs: \(device.advertisedServiceUUIDs.map { $0.uuidString }.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !device.services.isEmpty {
                    Text("Services: \(device.services.map { $0.id.uuidString }.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let range = device.estimatedRange {
                    Text(String(format: "Estimated range: %.1f m", range))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let coordinateText = coordinateText {
                    Text(coordinateText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            statusPill
        }
        .padding(16)
        .background(isTarget ? Color.red.opacity(0.18) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if isTarget {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.red, lineWidth: 2)
            }
        }
        .contextMenu {
            if isTarget {
                Button("Clear Target", role: .destructive, action: onClearTarget)
            } else {
                Button("Mark as Target", action: onMarkTarget)
            }
            Button("Active Geo", action: onActiveGeo)
            Button("Get Info", action: onGetInfo)
        }
        .onLongPressGesture {
            if isTarget {
                onClearTarget()
            } else {
                onMarkTarget()
            }
        }
    }

    private var signalIndicator: some View {
        VStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(accentColor)
            Text("\(device.lastRSSI) dBm")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(accentColor.opacity(0.15))
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

    private var accentColor: Color {
        if isTarget {
            return .red
        }
        return DeviceColorPalette.color(for: device.id)
    }

    private var coordinateText: String? {
        if let display = device.displayCoordinate {
            return "Coordinate: \(display)"
        }
        guard let location = device.lastKnownLocation?.coordinate else { return nil }
        let formatted = CoordinateFormatter.shared.string(from: location, mode: coordinateMode)
        return "Coordinate: \(formatted)"
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    MissionDeviceRow(
        device: BluetoothDevice(
            id: UUID(),
            name: "Responder Beacon",
            rssi: -48,
            state: .connected,
            services: [BluetoothServiceInfo(id: CBUUID(string: "180D"))],
            manufacturerData: "0A1B2C",
            estimatedRange: 2.0,
            locations: [DeviceGeo(coordinate: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090))]
        ),
        coordinateMode: .latitudeLongitude,
        isTarget: true,
        onMarkTarget: {},
        onClearTarget: {},
        onActiveGeo: {},
        onGetInfo: {}
    )
    .padding()
}
