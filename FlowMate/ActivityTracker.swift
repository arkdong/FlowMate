import Foundation
import Combine
#if os(macOS)
import AppKit

final class ActivityTracker: ObservableObject {
    @Published private(set) var currentSession: ActivitySession?
    @Published private(set) var todaySessions: [ActivitySession] = []

    var totalFocusedTime: TimeInterval {
        let finished = todaySessions.reduce(0) { $0 + $1.duration }
        let current = currentSession?.duration ?? 0
        return finished + current
    }

    private let sessionStore: SessionStore
    private let inspector = ActiveWindowInspector()
    private var timerCancellable: AnyCancellable?
    private var notifications: [NSObjectProtocol] = []
    private let calendar = Calendar.current
    private let ownBundleIdentifier = Bundle.main.bundleIdentifier

    init(sessionStore: SessionStore = SessionStore()) {
        self.sessionStore = sessionStore
        self.todaySessions = sessionStore.sessionsForToday()
        sessionStore.onCacheUpdate { [weak self] sessions in
            guard let self else { return }
            let startOfDay = self.calendar.startOfDay(for: Date())
            self.todaySessions = sessions.filter { $0.startDate >= startOfDay }
        }
        startObservingWorkspace()
        captureFrontmostApplication()
        startTimer()
    }

    deinit {
        stopObservingWorkspace()
        timerCancellable?.cancel()
    }

    func latestHighlights(maxCount: Int = 3) -> [ActivitySession] {
        var result: [ActivitySession] = []
        if let current = currentSession {
            result.append(current)
        }
        let remaining = max(0, maxCount - result.count)
        if remaining > 0 {
            let finished = todaySessions.sorted { $0.startDate > $1.startDate }
            result.append(contentsOf: finished.prefix(remaining))
        }
        return result
    }

    private func startTimer() {
        timerCancellable = Timer
            .publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        objectWillChange.send()
        captureFrontmostApplication()
    }

    private func refreshCurrentContext(for app: NSRunningApplication) {
        guard var current = currentSession else { return }
        let context = inspector.captureContext(for: app)
        current.appendContext(context)
        currentSession = current
    }

    private func startObservingWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let activation = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.beginSession(for: app)
        }
        notifications.append(activation)

        let termination = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier == self?.currentSession?.bundleIdentifier {
                self?.finishCurrentSession()
            }
        }
        notifications.append(termination)
    }

    private func stopObservingWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        for token in notifications {
            center.removeObserver(token)
        }
        notifications.removeAll()
    }

    private func beginSession(for app: NSRunningApplication) {
        if let ownBundleIdentifier, app.bundleIdentifier == ownBundleIdentifier {
            return
        }
        if let current = currentSession {
            if current.bundleIdentifier == app.bundleIdentifier {
                refreshCurrentContext(for: app)
                return
            }
            finishCurrentSession()
        }
        let context = inspector.captureContext(for: app)
        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        currentSession = ActivitySession(appName: appName,
                                         bundleIdentifier: app.bundleIdentifier ?? "unknown",
                                         startDate: Date(),
                                         initialContext: context)
    }

    private func finishCurrentSession(at date: Date = Date()) {
        guard var session = currentSession else { return }
        session.endDate = date
        sessionStore.append(session)
        todaySessions.append(session)
        trimSessionsToToday()
        currentSession = nil
    }

    private func trimSessionsToToday() {
        let startOfDay = calendar.startOfDay(for: Date())
        todaySessions.removeAll { $0.startDate < startOfDay }
    }

    private func captureFrontmostApplication() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            finishCurrentSession()
            return
        }
        beginSession(for: app)
    }
}
#else
final class ActivityTracker: ObservableObject {
    @Published private(set) var currentSession: ActivitySession?
    @Published private(set) var todaySessions: [ActivitySession] = []

    var totalFocusedTime: TimeInterval { 0 }

    init() {}

    func latestHighlights(maxCount: Int = 3) -> [ActivitySession] { [] }
}
#endif
