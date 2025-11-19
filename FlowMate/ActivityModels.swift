import Foundation

struct ActivityContext: Codable, Equatable {
    var windowTitle: String
    var url: URL?
    var documentPath: String?
    var contentSnippet: String?

    var readableDescription: String {
        if let snippet = contentSnippet, !snippet.isEmpty {
            return "\(windowTitle) · \(snippet)"
        } else if let url {
            return "\(windowTitle) · \(url.host ?? url.absoluteString)"
        } else if let documentPath {
            return "\(windowTitle) · \(documentPath)"
        } else {
            return windowTitle
        }
    }
}

struct ActivitySession: Identifiable, Codable, Equatable {
    let id: UUID
    let appName: String
    let bundleIdentifier: String
    let startDate: Date
    var endDate: Date?
    var contexts: [ActivityContext]

    var latestContext: ActivityContext? {
        contexts.last ?? contexts.first
    }

    var duration: TimeInterval {
        duration(asOf: Date())
    }

    func duration(asOf date: Date) -> TimeInterval {
        guard let end = endDate else {
            return date.timeIntervalSince(startDate)
        }
        return end.timeIntervalSince(startDate)
    }

    func finishing(at date: Date = Date()) -> ActivitySession {
        var copy = self
        copy.endDate = date
        return copy
    }

    mutating func appendContext(_ context: ActivityContext) {
        if contexts.last != context {
            contexts.append(context)
        } else {
            contexts[contexts.count - 1] = context
        }
    }

    init(id: UUID = UUID(),
         appName: String,
         bundleIdentifier: String,
         startDate: Date = Date(),
         endDate: Date? = nil,
         initialContext: ActivityContext) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.startDate = startDate
        self.endDate = endDate
        self.contexts = [initialContext]
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case appName
        case bundleIdentifier
        case startDate
        case endDate
        case contexts
        case context
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        appName = try container.decode(String.self, forKey: .appName)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        if let decodedContexts = try container.decodeIfPresent([ActivityContext].self, forKey: .contexts),
           !decodedContexts.isEmpty {
            contexts = decodedContexts
        } else if let legacyContext = try container.decodeIfPresent(ActivityContext.self, forKey: .context) {
            contexts = [legacyContext]
        } else {
            contexts = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(appName, forKey: .appName)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encode(contexts, forKey: .contexts)
    }
}
