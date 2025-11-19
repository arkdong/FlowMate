import Foundation

final class SessionStore {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "dev.flowmate.sessionstore", qos: .utility)
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private(set) var cachedSessions: [ActivitySession] = []
    private var cacheUpdateHandler: (([ActivitySession]) -> Void)?

    init(filename: String = "sessions.jsonl") {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = appSupport.appendingPathComponent("FlowMate", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent(filename)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        loadInitialCache()
    }

    func append(_ session: ActivitySession) {
        queue.async {
            self.appendSessionToDisk(session)
            DispatchQueue.main.async {
                self.cachedSessions.append(session)
                if self.cachedSessions.count > 500 {
                    self.cachedSessions.removeFirst(self.cachedSessions.count - 500)
                }
                self.cacheUpdateHandler?(self.cachedSessions)
            }
        }
    }

    func sessionsForToday(calendar: Calendar = .current) -> [ActivitySession] {
        let today = calendar.startOfDay(for: Date())
        return cachedSessions.filter { $0.startDate >= today }
    }

    private func loadInitialCache() {
        queue.async {
            let sessions = self.readSessionsFromDisk(limit: 500)
            DispatchQueue.main.async {
                self.cachedSessions = sessions
                self.cacheUpdateHandler?(sessions)
            }
        }
    }

    func onCacheUpdate(_ handler: @escaping ([ActivitySession]) -> Void) {
        cacheUpdateHandler = handler
        handler(cachedSessions)
    }

    private func appendSessionToDisk(_ session: ActivitySession) {
        do {
            let data = try encoder.encode(session)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(data)
                try handle.write(Data([0x0A]))
                try handle.close()
            } else {
                var combined = Data()
                combined.append(data)
                combined.append(0x0A)
                try combined.write(to: fileURL, options: .atomic)
            }
        } catch {
            print("SessionStore write error:", error)
        }
    }

    private func readSessionsFromDisk(limit: Int) -> [ActivitySession] {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
        defer { try? handle.close() }

        let data = handle.readDataToEndOfFile()
        guard let content = String(data: data, encoding: .utf8) else { return [] }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        let lastLines = lines.suffix(limit)
        var sessions: [ActivitySession] = []
        for line in lastLines {
            guard let data = line.data(using: .utf8),
                  let session = try? decoder.decode(ActivitySession.self, from: data) else { continue }
            sessions.append(session)
        }
        return sessions
    }
}
