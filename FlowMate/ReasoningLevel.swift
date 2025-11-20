import Foundation

enum ReasoningLevel: String, CaseIterable {
    case concise
    case balanced
    case deep

    var displayName: String {
        switch self {
        case .concise: return "Concise"
        case .balanced: return "Balanced"
        case .deep: return "Deep"
        }
    }

    var description: String {
        switch self {
        case .concise: return "Fast, minimal reasoning"
        case .balanced: return "Default reasoning depth"
        case .deep: return "Detailed, step-by-step reasoning"
        }
    }

    var iconName: String {
        switch self {
        case .concise: return "hare.fill"
        case .balanced: return "scalemass"
        case .deep: return "brain.head.profile"
        }
    }

    var summaryInstruction: String {
        switch self {
        case .concise:
            return "Analyze the app-usage data for this session and determine the two core topics that best represent the user's activity. Output only the two topics, separated by a comma, with no extra words."
        case .balanced:
            return "Analyze the app-usage data and describe the main patterns of this session. Briefly explain what the user was doing, including major app transitions and likely intent. Then identify the three core topics that best summarize the session. Limit your response to 3 sentences and end with: Core Topics: topic1, topic2, topic3"

        case .deep:
            return "Analyze the session’s app-usage timeline and infer the deeper goals behind the user’s actions. Describe how different apps relate to each other and what overall workflow or thought process they suggest. Highlight any high-level behaviors or motivations you detect. Limit your response to 5 sentences and end with: Core Topics: topic1, topic2, topic3, topic4"
        }
    }

    func goalPrompt(goal: String, sessionDescription: String) -> String {
        switch self {
        case .concise:
            return """
                    Goal: \(goal)
                    Session: \(sessionDescription)
                    Does this session directly help with the goal? Respond true or false.
                    """
        case .balanced:
            return "Placeholder balanced goal prompt."
        case .deep:
            return "Placeholder deep reasoning goal prompt."
        }
    }

    func consistencyPrompt(history: String, current: String) -> String {
        switch self {
        case .concise:
            return """
Past session context:
\(history)

Current session:
\(current)

Reply true if consistent, false otherwise.
"""
        case .balanced:
            return "Placeholder balanced consistency prompt."
        case .deep:
            return "Placeholder deep reasoning consistency prompt."
        }
    }

    var estimatedEnergyKWh: Double {
        switch self {
        case .concise: return 0.005
        case .balanced: return 0.01
        case .deep: return 0.02
        }
    }

    var estimatedCO2Kg: Double {
        switch self {
        case .concise: return 0.002
        case .balanced: return 0.004
        case .deep: return 0.008
        }
    }
}
