import SwiftUI
#if os(macOS)
import AppKit
import Combine
#endif

struct ContentView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tracker: ActivityTracker
    @AppStorage("dailyGoalHours") private var dailyGoalHours: Double = 4
    @State private var isFocusPromptVisible = false

    var body: some View {
        GlassDashboard(
            totalDuration: tracker.totalFocusedTime,
            currentSession: tracker.currentSession,
            highlights: tracker.latestHighlights(maxCount: 2),
            dailyGoalHours: $dailyGoalHours,
            isTrackingEnabled: tracker.isTrackingEnabled,
            onClose: { dismiss() },
            toggleTracking: { tracker.setTrackingEnabled(!tracker.isTrackingEnabled) },
            focusPromptVisibilityChanged: { isFocusPromptVisible = $0 }
        )
        .frame()
        .background(Color.clear)
        #if os(macOS)
        .background(TransparentWindowConfigurator(isMovableByBackground: !isFocusPromptVisible).allowsHitTesting(false))
        #endif
    }
}

struct GlassDashboard: View {
    @EnvironmentObject private var tracker: ActivityTracker

    let totalDuration: TimeInterval
    let currentSession: ActivitySession?
    let highlights: [ActivitySession]
    @Binding var dailyGoalHours: Double
    let isTrackingEnabled: Bool
    var onClose: (() -> Void)?
    let toggleTracking: () -> Void
    let focusPromptVisibilityChanged: (Bool) -> Void

    @State private var isGoalEditorPresented = false
    @State private var isFocusPromptPresented = false
    private let defaultFocusDuration: TimeInterval = 2 * 60 * 60
    @State private var focusDuration: TimeInterval = 2 * 60 * 60
    @State private var activeSession: FocusSession?
    @State private var sessionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var activeFocusRecord: FocusSessionRecord?
    @State private var focusHistory: [FocusSessionRecord] = []
    @State private var lastSessionCount: Int = 0
    @State private var summaryRecord: FocusSessionRecord?
    @State private var summaryText: String?
    @State private var summaryLoading = false
    @State private var focusGoal: String = ""
    @State private var evaluatedSessions: Set<UUID> = []
    private let minSessionDurationForEvaluation: TimeInterval = 30 // testing threshold

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                if let onClose {
                    CloseButton(action: onClose)
                }
                Spacer()
                TrackingStatusToggle(isActive: isTrackingEnabled, toggle: toggleTracking)
            }
            .padding(.bottom, 4)

            #if os(macOS)
            if !AccessibilityPermission.isGranted {
                PermissionBanner()
            }
            #endif

            SessionHeader(activeSession: activeSession, totalDuration: totalDuration)

            GlassProgressView(
                value: progressValue,
                dailyGoalHours: dailyGoalHours,
                editGoal: { isGoalEditorPresented = true },
                activeSession: activeSession
            )

            FocusControlButton(
                activeSession: activeSession,
                startAction: {
                    focusDuration = defaultFocusDuration
                    isFocusPromptPresented = true
                },
                stopAction: stopSession
            )
            if activeSession == nil && (!focusHistory.isEmpty || activeFocusRecord != nil) {
                LastSessionButton(latestRecord: focusHistory.last ?? activeFocusRecord)
            }

            if displayedSessions.isEmpty {
                Text("No sessions recorded yet. Start working in any app to see activity here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Activity")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    ForEach(displayedSessions) { session in
                        RealtimeSessionRow(session: session)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 36)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .blur(radius: 50)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: Color.black.opacity(0.35), radius: 40, y: 20)
        .sheet(isPresented: $isGoalEditorPresented) {
            GoalEditorView(hours: $dailyGoalHours)
                .presentationDetents([.fraction(0.25)])
        }
        .onReceive(sessionTimer) { _ in
            guard var session = activeSession else { return }
            session.elapsed = Date().timeIntervalSince(session.startDate)
            activeSession = session
            if session.elapsed >= session.target {
                stopSession()
            }
        }
        .onChange(of: tracker.todaySessions) { sessions in
            guard var record = activeFocusRecord else {
                lastSessionCount = sessions.count
                return
            }
            let delta = sessions.count - lastSessionCount
            if delta > 0 {
                let newSessions = sessions.suffix(delta)
                record.capturedSessions.append(contentsOf: newSessions)
                activeFocusRecord = record
                handleNewSessions(Array(newSessions))
            }
            lastSessionCount = sessions.count
        }
        .overlay {
            if isFocusPromptPresented {
                FocusPrompt(duration: $focusDuration,
                            isPresented: $isFocusPromptPresented,
                            action: { goal in
                                focusGoal = goal
                                startSession()
                            })
            }
            if let summary = summaryRecord {
                FocusSummaryView(record: summary,
                                 summaryText: summary.summary ?? summaryText,
                                 isLoading: summaryLoading) {
                    summaryRecord = nil
                    summaryText = nil
                    summaryLoading = false
                }
            }
        }
        .onChange(of: isFocusPromptPresented) { focusPromptVisibilityChanged($0) }
    }

    private var goalProgress: Double {
        let goalSeconds = max(dailyGoalHours, 0.25) * 3600
        return totalDuration / goalSeconds
    }

    private var displayedSessions: [ActivitySession] {
        Array(highlights.prefix(2))
    }

    private var progressValue: Double {
        if let session = activeSession {
            return min(session.elapsed / session.target, 1)
        }
        return min(goalProgress, 1)
    }

    private func startSession() {
        let startDate = Date()
        activeSession = FocusSession(startDate: startDate, target: focusDuration, elapsed: 0)
        activeFocusRecord = FocusSessionRecord(startDate: startDate,
                                               target: focusDuration,
                                               endDate: nil,
                                               capturedSessions: [],
                                               summary: nil,
                                               goal: focusGoal.isEmpty ? nil : focusGoal)
        lastSessionCount = tracker.todaySessions.count
        sessionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        isFocusPromptPresented = false
        evaluatedSessions.removeAll()
    }

    private func stopSession() {
        sessionTimer.upstream.connect().cancel()
        if var record = activeFocusRecord {
            record.endDate = Date()
            focusHistory.append(record)
            summaryRecord = record
            summaryLoading = true
            summaryText = nil
            Task {
                let service = GreenPTService.shared
                let summary = await service.summarize(record: record)
                await MainActor.run {
                    summaryText = summary ?? "Summary unavailable."
                    if let summary {
                        summaryRecord?.summary = summary
                        updateStoredSummary(recordID: record.id, summary: summary)
                    }
                    summaryLoading = false
                }
            }
        }
        activeSession = nil
        activeFocusRecord = nil
        focusGoal = ""
        evaluatedSessions.removeAll()
    }

    private func updateStoredSummary(recordID: UUID, summary: String) {
        if let index = focusHistory.firstIndex(where: { $0.id == recordID }) {
            focusHistory[index].summary = summary
        }
    }

    private func handleNewSessions(_ sessions: [ActivitySession]) {
        let goal = activeFocusRecord?.goal ?? ""
        for session in sessions {
            guard session.duration >= minSessionDurationForEvaluation else { continue }
            guard !evaluatedSessions.contains(session.id) else { continue }
            evaluatedSessions.insert(session.id)
            Task {
                if goal.isEmpty {
                    guard let record = activeFocusRecord else { return }
                    let priorSessions = record.capturedSessions.filter { $0.id != session.id }
                    guard !priorSessions.isEmpty else { return }
                    let consistent = await GreenPTService.shared.evaluateConsistency(current: session, history: priorSessions)
                    if let consistent = consistent, !consistent {
                        await NotificationManager.shared.sendNotification(
                            title: "Focus Alert",
                            body: "\(session.appName) may not align with the rest of this session"
                        )
                    }
                } else {
                    let relevant = await GreenPTService.shared.evaluate(goal: goal, session: session)
                    if let relevant = relevant, !relevant {
                        await NotificationManager.shared.sendNotification(
                            title: "Focus Alert",
                            body: "Are you DISTRACTED from your goal: \"\(goal)\"?"
                        )
                    }
                }
            }
        }
    }
}

struct GlassProgressView: View {
    let value: Double
    let dailyGoalHours: Double
    let editGoal: () -> Void
    let activeSession: FocusSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(activeSession == nil ? "Daily Goal" : "Session Progress")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if activeSession == nil {
                    Button("Edit", action: editGoal)
                        .font(.caption.bold())
                        .buttonStyle(.borderless)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                        .foregroundStyle(.primary)
                }
                Spacer()
                Text(progressLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)
            }
            if let session = activeSession {
                Text("Target \(session.target.formattedFocus)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(dailyGoalHours, specifier: "%.1f")h goal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let progressWidth = max(width * value, 0)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.cyan.opacity(0.9), .blue.opacity(0.9)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: progressWidth)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.4))
                                .blur(radius: 6)
                                .frame(width: progressWidth * 0.8)
                                .offset(y: 0)
                                .opacity(0.5)
                        )
                }
            }
            .frame(height: 16)
        }
    }

    private var progressLabel: String {
        if let session = activeSession {
            return "\(Int(value * 100))% · \(session.elapsed.formattedFocus)"
        }
        return "\(Int(value * 100))%"
    }
}

struct FocusControlButton: View {
    let activeSession: FocusSession?
    let startAction: () -> Void
    let stopAction: () -> Void

    var body: some View {
        Button {
            if activeSession == nil {
                startAction()
            } else {
                stopAction()
            }
        } label: {
            Label(activeSession == nil ? "Focus" : "Stop", systemImage: activeSession == nil ? "target" : "stop.fill")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(activeSession == nil
                              ? LinearGradient(colors: [.blue.opacity(0.9), .cyan.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                              : LinearGradient(colors: [.red.opacity(0.9), .orange.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                )
                .foregroundStyle(.white)
                .shadow(color: (activeSession == nil ? Color.blue : Color.red).opacity(0.3), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }
}

struct LastSessionButton: View {
    let latestRecord: FocusSessionRecord?
    @State private var showSummary = false

    var body: some View {
        Button {
            if latestRecord != nil {
                showSummary = true
            }
        } label: {
            Label("Last Session", systemImage: "clock.arrow.circlepath")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: [.green.opacity(0.9), .green.opacity(0.7)],
                                             startPoint: .leading,
                                             endPoint: .trailing))
                )
                .foregroundStyle(.white)
                .opacity(latestRecord == nil ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(latestRecord == nil)
        .sheet(isPresented: $showSummary) {
            if let record = latestRecord {
                FocusSummaryView(record: record,
                                 summaryText: record.summary,
                                 isLoading: false) {
                    showSummary = false
                }
            }
        }
        .padding(.top, 8)
    }
}

struct DashboardPill: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Image(systemName: icon)
                .imageScale(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
                )
        )
        .foregroundStyle(.white.opacity(0.95))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TrackingStatusToggle: View {
    let isActive: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Label {
                Text(isActive ? "Active" : "Paused")
                    .font(.caption.weight(.semibold))
            } icon: {
                Image(systemName: isActive ? "play.fill" : "pause.fill")
                    .font(.caption.weight(.bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill((isActive ? Color.green : Color.red).opacity(0.25))
            )
            .foregroundStyle(isActive ? Color.green : Color.red)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Tracking active" : "Tracking paused")
    }
}

struct SessionSummaryRow: View {
    let session: ActivitySession
    var referenceDate: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.appName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(session.duration(asOf: referenceDate).formattedBrief)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(session.latestContext?.windowTitle ?? "No Context")
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let snippet = session.latestContext?.contentSnippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let url = session.latestContext?.url {
                Text(url.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let path = session.latestContext?.documentPath {
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

struct RealtimeSessionRow: View {
    let session: ActivitySession

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            SessionSummaryRow(session: session, referenceDate: context.date)
        }
    }
}

struct GoalEditorView: View {
    @Binding var hours: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Daily Goal")
                .font(.headline)
            Text("Choose how many hours you want to focus each day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("Goal: \(hours, specifier: "%.1f")h")
                    .font(.title2.weight(.semibold))
                Spacer()
            }

            Slider(value: $hours, in: 0.5...12, step: 0.25)

            Stepper(value: $hours, in: 0.5...12, step: 0.25) {
                Text("Adjust: \(hours, specifier: "%.2f")h")
                    .font(.footnote)
            }

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
    }
}

struct FocusSummaryView: View {
    let record: FocusSessionRecord
    let summaryText: String?
    let isLoading: Bool
    let dismiss: () -> Void
    @State private var expandedApps: Set<String> = []

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Session Summary")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                }

                Text(summaryDuration)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text("AI Summary")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let goal = record.goal, !goal.isEmpty {
                    Text("Goal: \(goal)")
                        .font(.subheadline.weight(.medium))
                }

                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Summarizing session…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if let summaryText {
                    Text("AI Summary: \(summaryText)")
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .padding(.vertical, 4)
                }

                if record.capturedSessions.isEmpty {
                    Text("No app sessions recorded during this focus block.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(groupedSummaries) { summary in
                                DisclosureGroup(
                                    isExpanded: Binding(
                                        get: { expandedApps.contains(summary.appName) },
                                        set: { expanded in
                                            if expanded {
                                                expandedApps.insert(summary.appName)
                                            } else {
                                                expandedApps.remove(summary.appName)
                                            }
                                        }
                                    ),
                                    content: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(summary.contexts) { usage in
                                                VStack(alignment: .leading, spacing: 2) {
                                                    HStack {
                                                        Text(usage.duration.formattedBrief)
                                                            .font(.caption.monospacedDigit())
                                                        Spacer()
                                                        Text(usage.context.capturedAt.formatted(date: .omitted, time: .shortened))
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    Text(detailText(for: usage.context))
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(2)
                                                }
                                                .padding(8)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .fill(Color.white.opacity(0.05))
                                                )
                                            }
                                        }
                                        .padding(.top, 6)
                                    },
                                    label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(summary.appName)
                                                    .font(.headline)
                                                Text("\(summary.total.formattedFocus) · \(Int(summary.percent * 100))%")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                        }
                                        .padding(12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(.ultraThinMaterial)
                                        )
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .blur(radius: 30)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.4), radius: 30, y: 20)
        }
    }

    private var summaryDuration: String {
        let end = record.endDate ?? Date()
        let total = end.timeIntervalSince(record.startDate)
        return "Duration: \(total.formattedFocus)"
    }

    private func detailText(for context: ActivityContext) -> String {
        if let url = context.url {
            return "\(context.windowTitle) · \(url.absoluteString)"
        }
        if let path = context.documentPath {
            return "\(context.windowTitle) · \(path)"
        }
        return context.windowTitle
    }

    private var totalFocusDuration: TimeInterval {
        max((record.endDate ?? Date()).timeIntervalSince(record.startDate), 1)
    }

    private var groupedSummaries: [AppSummary] {
        let grouped = Dictionary(grouping: record.capturedSessions, by: { $0.appName })
        let summaries = grouped.map { key, value -> AppSummary in
            let total = value.reduce(0) { $0 + $1.duration }
            let percent = total / totalFocusDuration
            let contexts = value.flatMap { session in
                contextUsage(for: session)
            }
            return AppSummary(appName: key,
                              total: total,
                              percent: percent,
                              sessions: value,
                              contexts: contexts)
        }
        return summaries.sorted { $0.total > $1.total }
    }

    private func contextUsage(for session: ActivitySession) -> [ContextUsage] {
        guard !session.contexts.isEmpty else {
            let duration = session.duration
            let placeholder = ActivityContext(windowTitle: session.appName,
                                              url: nil,
                                              documentPath: nil,
                                              contentSnippet: nil,
                                              capturedAt: session.startDate)
            return [ContextUsage(context: placeholder, duration: duration)]
        }

        let sorted = session.contexts.sorted { $0.capturedAt < $1.capturedAt }
        var usages: [ContextUsage] = []
        for (index, context) in sorted.enumerated() {
            let start = context.capturedAt
            let end: Date
            if index + 1 < sorted.count {
                end = sorted[index + 1].capturedAt
            } else {
                end = session.endDate ?? Date()
            }
            let duration = max(end.timeIntervalSince(start), 0)
            usages.append(ContextUsage(context: context, duration: duration))
        }
        return usages
    }
}

struct FocusPrompt: View {
    @Binding var duration: TimeInterval
    @Binding var isPresented: Bool
    let action: (String) -> Void
    @State private var goalText: String = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 20) {
                Text("Start Focus Session")
                    .font(.title3.weight(.semibold))
                Text("Choose how long you want to focus for this block.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(duration.formattedFocus)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Slider(value: Binding(
                    get: { duration / 60 },
                    set: { duration = $0 * 60 }
                ), in: 1...120, step: 1)

                TextField("Optional focus goal (e.g., \"Max likelihood notes\")", text: $goalText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    action(goalText.trimmingCharacters(in: .whitespacesAndNewlines))
                    isPresented = false
                } label: {
                    Text("Start")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .circular)
                                .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                        )
                        .foregroundStyle(.white)
                }

                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .blur(radius: 40)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.4), radius: 30, y: 20)
        }
    }
}

struct SessionHeader: View {
    let activeSession: FocusSession?
    let totalDuration: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(activeSession == nil ? "Today" : "Session")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
            } icon: {
                Image(systemName: activeSession == nil ? "hourglass" : "target")
                    .font(.system(size: 22, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .symbolRenderingMode(.multicolor)
            .padding(.bottom, -8)

            if let session = activeSession {
                Text(session.elapsed.formattedClockStyle)
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Elapsed focus time")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(totalDuration.formattedClockStyle)
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Tracked focus time")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if os(macOS)
struct PermissionBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Accessibility access required")
                .font(.caption.weight(.semibold))
            Text("Grant FlowMate permission in System Settings → Privacy & Security → Accessibility to capture app context.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Open Settings", action: openAccessibilitySettings)
                .font(.caption.bold())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.2))
        )
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif

struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color(red: 1.0, green: 0.35, blue: 0.32))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                        )
                )
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
        .help("Close Dashboard")
    }
}

#if os(macOS)
struct TransparentWindowConfigurator: NSViewRepresentable {
    let isMovableByBackground: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.styleMask = [.borderless]
        window.hasShadow = true
        window.isMovableByWindowBackground = isMovableByBackground
        window.level = .normal
    }
}
#endif

struct FocusSession {
    let startDate: Date
    let target: TimeInterval
    var elapsed: TimeInterval
}

struct FocusSessionRecord: Identifiable {
    let id = UUID()
    let startDate: Date
    let target: TimeInterval
    var endDate: Date?
    var capturedSessions: [ActivitySession]
    var summary: String?
    var goal: String?
}

struct AppSummary: Identifiable {
    let id = UUID()
    let appName: String
    let total: TimeInterval
    let percent: Double
    let sessions: [ActivitySession]
    let contexts: [ContextUsage]
}

struct ContextUsage: Identifiable {
    let id = UUID()
    let context: ActivityContext
    let duration: TimeInterval
}

extension TimeInterval {
    var formattedClockStyle: String {
        let totalSeconds = max(Int(self), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    var formattedBrief: String {
        let totalSeconds = max(Int(self), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return String(format: "%02dm %02ds", minutes, seconds)
    }

    var formattedFocus: String {
        let totalMinutes = max(Int(self / 60), 1)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

#Preview {
    ContentView()
        .environmentObject(ActivityTracker())
}
