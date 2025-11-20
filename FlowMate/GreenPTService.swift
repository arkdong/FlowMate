import Foundation

struct GreenPTService {
    static let shared = GreenPTService()
    private let endpoint = URL(string: "https://api.greenpt.ai/v1/chat/completions")!
    private let apiKey = "sk-hGORmAVgT3aF0YiBTxUqRp7mhxurgUCyntMSWR3Bv1A"

    func summarize(record: FocusSessionRecord, model: GreenPTModel, reasoning: ReasoningLevel) async -> String? {
        let prompt = buildPrompt(for: record, reasoning: reasoning)
        let messages = [
            ChatMessage(role: "user", content: prompt)
        ]
        return await send(messages: messages, model: model)
    }

    func sendHelloTest(model: GreenPTModel = .greenL) async -> String? {
        let messages = [
            ChatMessage(role: "user", content: "Hello, how are you?")
        ]
        return await send(messages: messages, model: model)
    }

    func evaluate(goal: String, session: ActivitySession, model: GreenPTModel, reasoning: ReasoningLevel) async -> Bool? {
        let description = describe(session: session)
        let prompt = reasoning.goalPrompt(goal: goal, sessionDescription: description)
        guard let response = await send(messages: [ChatMessage(role: "user", content: prompt)], model: model) else {
            return nil
        }
        let trimmed = response.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "true" { return true }
        if trimmed == "false" { return false }
        return nil
    }

    private func buildPrompt(for record: FocusSessionRecord, reasoning: ReasoningLevel) -> String {
        var lines: [String] = []
        let duration = (record.endDate ?? Date()).timeIntervalSince(record.startDate).formattedFocus
        lines.append("Focus session duration: \(duration).")
        let appSummary = Dictionary(grouping: record.capturedSessions, by: { $0.appName })
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.duration }) }
            .sorted { $0.1 > $1.1 }
        if !appSummary.isEmpty {
            lines.append("Apps used with total time:")
            for (app, total) in appSummary.prefix(5) {
                let percent = total / max((record.endDate ?? Date()).timeIntervalSince(record.startDate), 1)
                lines.append("- \(app): \(total.formattedFocus) (\(Int(percent * 100))%)")
            }
        }

        let topicAggregates = aggregateContexts(from: record)
        if !topicAggregates.isEmpty {
            lines.append("Primary topics/pages encountered:")
            for aggregate in topicAggregates.prefix(8) {
                lines.append("- \(aggregate.description): \(aggregate.duration.formattedFocus) (\(Int(aggregate.percent * 100))%)")
            }
        } else {
            lines.append("No detailed context captured; infer from app usage only.")
        }
        lines.append(reasoning.summaryInstruction)
        return lines.joined(separator: "\n")
    }

    private func aggregateContexts(from record: FocusSessionRecord) -> [ContextAggregate] {
        let totalDuration = max((record.endDate ?? Date()).timeIntervalSince(record.startDate), 1)
        var map: [String: ContextAggregate] = [:]

        for session in record.capturedSessions {
            for segment in contextSegments(for: session) {
                let key = segment.key
                if map[key] == nil {
                    map[key] = ContextAggregate(description: segment.description, duration: 0, percent: 0)
                }
                map[key]?.duration += segment.duration
            }
        }

        var aggregates = Array(map.values)
        for index in aggregates.indices {
            aggregates[index].percent = aggregates[index].duration / totalDuration
        }
        aggregates.sort { $0.duration > $1.duration }
        return aggregates
    }

    private func contextSegments(for session: ActivitySession) -> [(key: String, description: String, duration: TimeInterval)] {
        var segments: [(ActivityContext, Date)] = []
        let contexts = session.contexts
        if contexts.isEmpty {
            let placeholder = ActivityContext(windowTitle: session.appName,
                                              url: nil,
                                              documentPath: nil,
                                              contentSnippet: nil,
                                              capturedAt: session.startDate)
            segments.append((placeholder, session.endDate ?? Date()))
        } else {
            let sorted = contexts.sorted { $0.capturedAt < $1.capturedAt }
            for (index, context) in sorted.enumerated() {
                let endDate: Date
                if index + 1 < sorted.count {
                    endDate = sorted[index + 1].capturedAt
                } else {
                    endDate = session.endDate ?? Date()
                }
                segments.append((context, endDate))
            }
        }

        return segments.compactMap { context, end in
            let start = context.capturedAt
            let duration = max(end.timeIntervalSince(start), 0)
            let description = readableDescription(for: context)
            let key = "\(context.windowTitle)|\(context.url?.absoluteString ?? "")|\(context.documentPath ?? "")"
            return (key, description, duration)
        }
    }

    private func readableDescription(for context: ActivityContext) -> String {
        if let url = context.url {
            return "\(context.windowTitle) (\(url.absoluteString))"
        }
        if let path = context.documentPath {
            return "\(context.windowTitle) (\(path))"
        }
        if let snippet = context.contentSnippet, !snippet.isEmpty {
            return "\(context.windowTitle) · \(snippet.prefix(80))"
        }
        return context.windowTitle
    }

    private func describe(session: ActivitySession) -> String {
        var parts: [String] = []
        parts.append("App: \(session.appName)")
        parts.append("Duration: \(session.duration.formattedFocus)")
        if !session.contexts.isEmpty {
            parts.append("Contexts:")
            let usage = contextUsage(for: session)
            for segment in usage.prefix(5) {
                parts.append("- \(segment.description) for \(segment.duration.formattedFocus)")
            }
        } else if let context = session.latestContext {
            parts.append("Context: \(readableDescription(for: context))")
        }
        return parts.joined(separator: "\n")
    }

    private func contextUsage(for session: ActivitySession) -> [ContextAggregate] {
        var usage: [ContextAggregate] = []
        let segments = contextSegments(for: session)
        for segment in segments {
            usage.append(ContextAggregate(description: segment.description, duration: segment.duration, percent: 0))
        }
        return usage
    }
    
    func evaluateConsistency(current: ActivitySession, history: [ActivitySession], model: GreenPTModel, reasoning: ReasoningLevel) async -> Bool? {
        let historyDescription = history.map { describe(session: $0) }.joined(separator: "\n\n")
        let currentDescription = describe(session: current)
        let prompt = reasoning.consistencyPrompt(history: historyDescription, current: currentDescription)
        guard let response = await send(messages: [ChatMessage(role: "user", content: prompt)], model: model) else {
            return nil
        }
        let trimmed = response.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "true" { return true }
        if trimmed == "false" { return false }
        return nil
    }

    private func send(messages: [ChatMessage], model: GreenPTModel) async -> String? {
        let payload: [String: Any] = [
            "model": model.rawValue,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false
        ]
        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                if let body = String(data: data, encoding: .utf8) {
                    print("GreenPT error response:", body)
                }
                return nil
            }
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            if let choices = json?["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        } catch {
            print("GreenPT request failed:", error)
            return nil
        }
    }
}

private struct ChatMessage {
    let role: String
    let content: String
}

private struct ContextAggregate {
    let description: String
    var duration: TimeInterval
    var percent: Double
}
