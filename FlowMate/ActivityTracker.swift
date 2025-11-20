import Foundation
import Combine
#if os(macOS)
import AppKit

final class ActivityTracker: ObservableObject {
    @Published private(set) var currentSession: ActivitySession?
    @Published private(set) var todaySessions: [ActivitySession] = []
    @Published private(set) var isTrackingEnabled: Bool = true

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
    private let breakThreshold: TimeInterval = 1000 // testing threshold
    private var breakTimer: Timer?
    private var breakSessionID: UUID?

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
        guard isTrackingEnabled else { return }
        objectWillChange.send()
        captureFrontmostApplication()
    }

    private func refreshCurrentContext(for app: NSRunningApplication) {
        guard isTrackingEnabled else { return }
        guard let current = currentSession else { return }
        let context = inspector.captureContext(for: app)
        if let latest = current.latestContext, latest.hasSameContent(as: context) {
            return
        }
        finishCurrentSession(at: context.capturedAt)
        beginSession(for: app, contextOverride: context, startDate: context.capturedAt)
    }

    private func startObservingWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let activation = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard self?.isTrackingEnabled == true else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.beginSession(for: app)
        }
        notifications.append(activation)

        let termination = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard self?.isTrackingEnabled == true else { return }
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

    private func beginSession(for app: NSRunningApplication,
                              contextOverride: ActivityContext? = nil,
                              startDate: Date = Date()) {
        guard isTrackingEnabled else { return }
        if let ownBundleIdentifier, app.bundleIdentifier == ownBundleIdentifier {
            return
        }
        if let current = currentSession {
            if current.bundleIdentifier == app.bundleIdentifier,
               contextOverride == nil {
                refreshCurrentContext(for: app)
                return
            }
            finishCurrentSession(at: startDate)
        }
        let context = contextOverride ?? inspector.captureContext(for: app)
        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let session = ActivitySession(appName: appName,
                                      bundleIdentifier: app.bundleIdentifier ?? "unknown",
                                      startDate: contextOverride?.capturedAt ?? startDate,
                                      initialContext: context)
        currentSession = session
        scheduleBreakReminder(for: session)
    }

    private func finishCurrentSession(at date: Date = Date()) {
        guard var session = currentSession else { return }
        session.endDate = date
        sessionStore.append(session)
        todaySessions.append(session)
        trimSessionsToToday()
        currentSession = nil
        invalidateBreakReminder()
    }

    private func trimSessionsToToday() {
        let startOfDay = calendar.startOfDay(for: Date())
        todaySessions.removeAll { $0.startDate < startOfDay }
    }

    private func captureFrontmostApplication() {
        guard isTrackingEnabled else { return }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            finishCurrentSession()
            return
        }
        beginSession(for: app)
    }

    func setTrackingEnabled(_ enabled: Bool) {
        guard enabled != isTrackingEnabled else { return }
        isTrackingEnabled = enabled
        if enabled {
            captureFrontmostApplication()
        } else {
            finishCurrentSession()
        }
    }

    private func scheduleBreakReminder(for session: ActivitySession) {
        guard breakThreshold > 0 else { return }
        invalidateBreakReminder()
        breakSessionID = session.id
        breakTimer = Timer.scheduledTimer(withTimeInterval: breakThreshold, repeats: false) { [weak self] _ in
            guard let self,
                  let current = self.currentSession,
                  current.id == session.id else { return }
            NotificationManager.shared.sendNotification(
                title: "Break Reminder",
                body: "You've been working hard, time to take a 5 minute break?"
            )
        }
        RunLoop.main.add(breakTimer!, forMode: .common)
    }

    private func invalidateBreakReminder() {
        breakTimer?.invalidate()
        breakTimer = nil
        breakSessionID = nil
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
