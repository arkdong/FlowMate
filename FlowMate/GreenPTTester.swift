//import Foundation
//import Dispatch
//
//let semaphore = DispatchSemaphore(value: 0)
//var capturedResponse: String?
//
//struct GreenPTTesterService {
//    let endpoint = URL(string: "https://api.greenpt.ai/v1/chat/completions")!
//    let apiKey = "sk-hGORmAVgT3aF0YiBTxUqRp7mhxurgUCyntMSWR3Bv1A"
//
//    func sendHelloTest() async -> String? {
//        let requestBody: [String: Any] = [
//            "model": "green-l",
//            "messages": [
//                ["role": "user", "content": "Hello, how are you?"]
//            ],
//            "stream": false
//        ]
//
//        do {
//            var request = URLRequest(url: endpoint)
//            request.httpMethod = "POST"
//            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
//            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
//            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
//
//            let (data, response) = try await URLSession.shared.data(for: request)
//            guard let httpResponse = response as? HTTPURLResponse,
//                  (200...299).contains(httpResponse.statusCode) else {
//                if let raw = String(data: data, encoding: .utf8) {
//                    print("Error response:", raw)
//                }
//                return nil
//            }
//            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//               let choices = json["choices"] as? [[String: Any]],
//               let first = choices.first,
//               let message = first["message"] as? [String: Any],
//               let content = message["content"] as? String {
//                return content.trimmingCharacters(in: .whitespacesAndNewlines)
//            }
//            return nil
//        } catch {
//            print("Request error:", error)
//            return nil
//        }
//    }
//}
//
//print("Sending sample request to GreenPT…")
//
//Task {
//    let service = GreenPTTesterService()
//    capturedResponse = await service.sendHelloTest()
//    semaphore.signal()
//}
//
//semaphore.wait()
//
//if let response = capturedResponse {
//    print("Response:", response)
//} else {
//    print("Request failed or returned empty response.")
//}
