import Foundation

final class LogManager {
    private let queue = DispatchQueue(label: "com.bluek9.log", qos: .utility)
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL

    init(filename: String = "mission-log.json") {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        fileURL = documents.appendingPathComponent(filename)
    }

    func load() -> [MissionLogEntry] {
        (try? Data(contentsOf: fileURL)).flatMap { try? decoder.decode([MissionLogEntry].self, from: $0) } ?? []
    }

    func persist(entries: [MissionLogEntry]) {
        let dataWork = { [encoder] in
            do {
                let data = try encoder.encode(entries)
                try data.write(to: self.fileURL, options: .atomic)
            } catch {
                print("Failed to write mission log: \(error)")
            }
        }

        if Thread.isMainThread {
            queue.async(execute: dataWork)
        } else {
            dataWork()
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func logURL() -> URL {
        fileURL
    }
}
