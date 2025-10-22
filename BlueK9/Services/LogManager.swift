import Foundation

struct LogSnapshot {
    let entries: [MissionLogEntry]
    let logs: [MissionLogDescriptor]
    let activeLog: MissionLogDescriptor
}

final class LogManager {
    private struct LogIndex: Codable {
        var logs: [MissionLogDescriptor]
        var activeLogID: UUID?
    }

    private let queue = DispatchQueue(label: "com.bluek9.log", qos: .utility)
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let directory: URL
    private let indexURL: URL
    private var index: LogIndex
    private let csvDateFormatter: ISO8601DateFormatter

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        directory = documents.appendingPathComponent("MissionLogs", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json")

        csvDateFormatter = ISO8601DateFormatter()
        csvDateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? decoder.decode(LogIndex.self, from: data) {
            index = decoded
        } else {
            let descriptor = MissionLogDescriptor(name: "Mission Log")
            index = LogIndex(logs: [descriptor], activeLogID: descriptor.id)
            saveIndex()
            write([], to: descriptor.id)
        }

        ensureActiveLogExists()
    }

    func bootstrap() -> LogSnapshot {
        queue.sync {
            ensureActiveLogExists()
            let activeID = index.activeLogID ?? index.logs.first!.id
            let entries = loadEntries(for: activeID)
            return makeSnapshot(entries: entries, activeID: activeID)
        }
    }

    func allLogs() -> [MissionLogDescriptor] {
        queue.sync { index.logs }
    }

    func activeLogDescriptor() -> MissionLogDescriptor {
        queue.sync {
            ensureActiveLogExists()
            let activeID = index.activeLogID ?? index.logs.first!.id
            return descriptor(for: activeID) ?? index.logs.first!
        }
    }

    @discardableResult
    func persist(entries: [MissionLogEntry]) -> LogSnapshot {
        queue.sync {
            ensureActiveLogExists()
            let activeID = index.activeLogID ?? index.logs.first!.id
            write(entries, to: activeID)
            touchDescriptor(id: activeID)
            return makeSnapshot(entries: entries, activeID: activeID)
        }
    }

    func createLog(named rawName: String) -> LogSnapshot {
        queue.sync {
            let descriptor = MissionLogDescriptor(name: sanitize(rawName))
            index.logs.append(descriptor)
            index.logs.sort { $0.createdAt < $1.createdAt }
            index.activeLogID = descriptor.id
            saveIndex()
            write([], to: descriptor.id)
            return makeSnapshot(entries: [], activeID: descriptor.id)
        }
    }

    func renameLog(id: UUID, to rawName: String) -> LogSnapshot {
        queue.sync {
            guard var descriptor = descriptor(for: id) else {
                return bootstrap()
            }
            descriptor.name = sanitize(rawName)
            descriptor.updatedAt = Date()
            replace(descriptor)
            saveIndex()
            let activeID = index.activeLogID ?? descriptor.id
            let entries = loadEntries(for: activeID)
            return makeSnapshot(entries: entries, activeID: activeID)
        }
    }

    func selectLog(id: UUID) -> LogSnapshot {
        queue.sync {
            guard descriptor(for: id) != nil else {
                return bootstrap()
            }
            index.activeLogID = id
            saveIndex()
            let entries = loadEntries(for: id)
            return makeSnapshot(entries: entries, activeID: id)
        }
    }

    func deleteLog(id: UUID) -> LogSnapshot {
        queue.sync {
            index.logs.removeAll { $0.id == id }
            let file = fileURL(for: id)
            try? FileManager.default.removeItem(at: file)
            ensureActiveLogExists()
            saveIndex()
            let activeID = index.activeLogID ?? index.logs.first!.id
            let entries = loadEntries(for: activeID)
            return makeSnapshot(entries: entries, activeID: activeID)
        }
    }

    func deleteAllLogs() -> LogSnapshot {
        queue.sync {
            for descriptor in index.logs {
                let file = fileURL(for: descriptor.id)
                try? FileManager.default.removeItem(at: file)
            }
            let descriptor = MissionLogDescriptor(name: "Mission Log")
            index = LogIndex(logs: [descriptor], activeLogID: descriptor.id)
            saveIndex()
            write([], to: descriptor.id)
            return makeSnapshot(entries: [], activeID: descriptor.id)
        }
    }

    func exportCSV(for id: UUID? = nil) -> URL {
        queue.sync {
            ensureActiveLogExists()
            let targetID = id ?? index.activeLogID ?? index.logs.first!.id
            let entries = loadEntries(for: targetID)
            let csv = csvString(from: entries)
            let filename = "mission-log-\(targetID.uuidString).csv"
            let exportURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try? csv.data(using: .utf8)?.write(to: exportURL, options: .atomic)
            return exportURL
        }
    }

    // MARK: - Private helpers

    private func sanitize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Log" : trimmed
    }

    private func ensureActiveLogExists() {
        if index.logs.isEmpty {
            let descriptor = MissionLogDescriptor(name: "Mission Log")
            index.logs = [descriptor]
            index.activeLogID = descriptor.id
            saveIndex()
            write([], to: descriptor.id)
            return
        }

        if let activeID = index.activeLogID, descriptor(for: activeID) != nil {
            return
        }

        let descriptor = index.logs.sorted { $0.createdAt < $1.createdAt }.first!
        index.activeLogID = descriptor.id
        saveIndex()
        if !FileManager.default.fileExists(atPath: fileURL(for: descriptor.id).path) {
            write([], to: descriptor.id)
        }
    }

    private func descriptor(for id: UUID) -> MissionLogDescriptor? {
        index.logs.first(where: { $0.id == id })
    }

    private func replace(_ descriptor: MissionLogDescriptor) {
        if let indexPosition = index.logs.firstIndex(where: { $0.id == descriptor.id }) {
            index.logs[indexPosition] = descriptor
        } else {
            index.logs.append(descriptor)
        }
    }

    private func touchDescriptor(id: UUID) {
        if var descriptor = descriptor(for: id) {
            descriptor.updatedAt = Date()
            replace(descriptor)
            saveIndex()
        }
    }

    private func makeSnapshot(entries: [MissionLogEntry], activeID: UUID) -> LogSnapshot {
        let logs = index.logs.sorted { $0.createdAt < $1.createdAt }
        let active = descriptor(for: activeID) ?? logs.first!
        return LogSnapshot(entries: entries, logs: logs, activeLog: active)
    }

    private func write(_ entries: [MissionLogEntry], to id: UUID) {
        let url = fileURL(for: id)
        do {
            let data = try encoder.encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to write mission log: \(error)")
        }
    }

    private func loadEntries(for id: UUID) -> [MissionLogEntry] {
        let url = fileURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([MissionLogEntry].self, from: data)) ?? []
    }

    private func saveIndex() {
        do {
            let data = try encoder.encode(index)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            print("Failed to save log index: \(error)")
        }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("log-\(id.uuidString).json")
    }

    private func csvString(from entries: [MissionLogEntry]) -> String {
        let header = "timestamp,type,message,metadata\n"
        let rows = entries.map { entry -> String in
            let timestamp = csvDateFormatter.string(from: entry.timestamp)
            let metadataString = metadataSummary(entry.metadata)
            let fields = [timestamp, entry.type.rawValue, entry.message, metadataString]
            return fields.map(csvEscaped).joined(separator: ",")
        }
        return header + rows.joined(separator: "\n")
    }

    private func metadataSummary(_ metadata: [String: String]?) -> String {
        guard let metadata, !metadata.isEmpty else { return "" }
        return metadata.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    private func csvEscaped(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\n") || value.contains("\"") || value.contains("\r")
        if !needsQuoting {
            return value
        }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
