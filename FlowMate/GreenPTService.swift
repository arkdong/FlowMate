import Foundation

struct GreenPTService {
    static let shared = GreenPTService()
    private let endpoint = URL(string: "https://api.greenpt.ai/v1/chat/completions")!
    private let apiKey = "sk-hGORmAVgT3aF0YiBTxUqRp7mhxurgUCyntMSWR3Bv1A"

    func summarize(record: FocusSessionRecord) async -> String? {
        let prompt = buildPrompt(for: record)
        let messages = [
            ChatMessage(role: "user", content: prompt)
        ]
        return await send(messages: messages)
    }

    func sendHelloTest() async -> String? {
        let messages = [
            ChatMessage(role: "user", content: "Hello, how are you?")
        ]
        return await send(messages: messages)
    }

    private func buildPrompt(for record: FocusSessionRecord) -> String {
        var lines: [String] = []
        let duration = (record.endDate ?? Date()).timeIntervalSince(record.startDate).formattedFocus
        lines.append("Focus session duration: \(duration).")
        lines.append("Apps used with time spent:")
        let grouped = Dictionary(grouping: record.capturedSessions, by: { $0.appName })
        for (app, sessions) in grouped {
            let total = sessions.reduce(0) { $0 + $1.duration }.formattedFocus
            lines.append("- \(app): \(total)")
        }
        lines.append("Provide one sentence summary mentioning the primary activities.")
        return lines.joined(separator: "\n")
    }

    private func send(messages: [ChatMessage]) async -> String? {
        let payload: [String: Any] = [
            "model": "green-l",
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
