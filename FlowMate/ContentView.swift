import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tracker: ActivityTracker
    @AppStorage("dailyGoalHours") private var dailyGoalHours: Double = 4

    var body: some View {
        GlassDashboard(
            totalDuration: tracker.totalFocusedTime,
            currentSession: tracker.currentSession,
            highlights: tracker.latestHighlights(maxCount: 2),
            dailyGoalHours: $dailyGoalHours,
            onClose: { dismiss() }
        )
        .frame(minWidth: 440, minHeight: 360)
        .background(Color.clear)
        #if os(macOS)
        .background(TransparentWindowConfigurator().allowsHitTesting(false))
        #endif
    }
}

struct GlassDashboard: View {
    let totalDuration: TimeInterval
    let currentSession: ActivitySession?
    let highlights: [ActivitySession]
    @Binding var dailyGoalHours: Double
    var onClose: (() -> Void)?

    @State private var isGoalEditorPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let onClose {
                CloseButton(action: onClose)
                    .padding(.bottom, 4)
            }

            #if os(macOS)
            if !AccessibilityPermission.isGranted {
                PermissionBanner()
            }
            #endif

            Label {
                Text("Today")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
            } icon: {
                Image(systemName: "hourglass")
                    .font(.system(size: 22, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .symbolRenderingMode(.multicolor)
            .padding(.bottom, -8)

            VStack(alignment: .leading, spacing: 4) {
                Text(totalDuration.formattedClockStyle)
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Tracked focus time")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GlassProgressView(
                value: min(goalProgress, 1),
                dailyGoalHours: dailyGoalHours,
                editGoal: { isGoalEditorPresented = true }
            )

            HStack(spacing: 12) {
                DashboardPill(icon: "bolt.fill", text: currentSession?.appName ?? "Idle")
                DashboardPill(icon: "text.alignleft",
                              text: currentSession?.latestContext?.contentSnippet
                                ?? currentSession?.latestContext?.readableDescription
                                ?? "No active context")
            }
            .padding(.top, 4)

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
    }

    private var goalProgress: Double {
        let goalSeconds = max(dailyGoalHours, 0.25) * 3600
        return totalDuration / goalSeconds
    }

    private var displayedSessions: [ActivitySession] {
        Array(highlights.prefix(2))
    }
}

struct GlassProgressView: View {
    let value: Double
    let dailyGoalHours: Double
    let editGoal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Daily Goal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)
            }
            Text("\(dailyGoalHours, specifier: "%.1f")h goal")
                .font(.caption2)
                .foregroundStyle(.secondary)

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
        window.isMovableByWindowBackground = true
        window.level = .normal
    }
}
#endif

private extension TimeInterval {
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
}

#Preview {
    ContentView()
        .environmentObject(ActivityTracker())
}
