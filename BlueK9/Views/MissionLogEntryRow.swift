import SwiftUI

struct MissionLogEntryRow: View {
    let entry: MissionLogEntry
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.type.rawValue.capitalized)
                        .font(.headline)
                    Spacer()
                    Text(formatter.string(from: entry.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(entry.message)
                    .font(.subheadline)
                if let metadata = entry.metadata, !metadata.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            Text("\(key): \(value)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var color: Color {
        switch entry.type {
        case .error: return .red
        case .scanStarted, .scanStopped: return .blue
        case .deviceConnected, .deviceDiscovered, .deviceServices, .deviceUpdated: return .green
        case .locationUpdate: return .teal
        case .deviceDisconnected: return .orange
        case .note: return .purple
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    MissionLogEntryRow(entry: MissionLogEntry(type: .deviceDiscovered, message: "Responder Beacon", metadata: ["rssi": "-42"]))
        .padding()
}
