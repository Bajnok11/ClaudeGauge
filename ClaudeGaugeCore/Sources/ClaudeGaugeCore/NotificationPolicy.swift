import Foundation

/// Something worth telling the user about, decided purely from two
/// consecutive snapshots plus preferences.
public enum UsageAlert: Equatable, Sendable {
    /// Usage climbed past a threshold it wasn't past before.
    case crossedThreshold(percent: Int, metric: String, current: Double)
    /// A usage window rolled over and freed capacity back up.
    case windowReset(metric: String)

    public var title: String {
        switch self {
        case .crossedThreshold(let percent, let metric, _):
            return "\(metric) usage at \(percent)%"
        case .windowReset(let metric):
            return "\(metric) limit reset"
        }
    }

    public var body: String {
        switch self {
        case .crossedThreshold(_, let metric, let current):
            return "You've used \(Int(current.rounded()))% of your \(metric.lowercased()) limit."
        case .windowReset(let metric):
            return "Your \(metric.lowercased()) usage window has rolled over."
        }
    }
}

/// Decides which alerts to fire, given what's already been fired.
///
/// Written as a pure value type with no `UserNotifications` import so the
/// interesting part — "don't spam the same threshold every poll" — is unit
/// testable without a notification centre or a running app. The app layer
/// owns delivery; this owns the decision.
///
/// The rule that makes it non-trivial: a threshold fires on the *rising
/// edge* only. Polling every minute at 86% must not produce a notification
/// every minute; it fires once when 85% is first crossed, and only re-arms
/// after usage drops back below that threshold (i.e. the window reset).
public struct NotificationPolicy: Equatable, Sendable {
    /// Thresholds already fired for the current window, per metric key.
    private var firedThresholds: [String: Set<Int>]
    /// Last seen percentage per metric, used to detect a window rollover.
    private var lastPercent: [String: Double]

    public init() {
        firedThresholds = [:]
        lastPercent = [:]
    }

    /// How far usage must fall for it to count as a genuine window reset
    /// rather than ordinary noise. Utilization can tick down slightly as
    /// older requests age out of a rolling window, and treating every small
    /// dip as a reset would re-arm thresholds and cause repeat notifications
    /// — exactly what the rising-edge rule exists to prevent.
    private static let resetDropThreshold: Double = 10

    public mutating func evaluate(
        snapshot: UsageSnapshot,
        preferences: Preferences
    ) -> [UsageAlert] {
        guard preferences.notificationsEnabled, snapshot.hasData else {
            // Still record position so re-enabling notifications doesn't
            // immediately fire for thresholds crossed while they were off.
            record(snapshot)
            return []
        }

        var alerts: [UsageAlert] = []
        let metrics: [(key: String, label: String, percent: Double)] = [
            ("session", snapshot.primaryLabel, snapshot.sessionPercent),
            ("weekly", snapshot.secondaryLabel, snapshot.weeklyPercent)
        ]

        for metric in metrics {
            let previous = lastPercent[metric.key]
            var fired = firedThresholds[metric.key] ?? []

            if let previous, previous - metric.percent >= Self.resetDropThreshold {
                // Window rolled over: re-arm every threshold below where we
                // now sit, and tell the user if they asked to hear about it.
                fired = fired.filter { Double($0) <= metric.percent }
                if preferences.notifyOnReset {
                    alerts.append(.windowReset(metric: metric.label))
                }
            }

            for threshold in preferences.notificationThresholds.sorted() {
                let crossed = metric.percent >= Double(threshold)
                if crossed && !fired.contains(threshold) {
                    fired.insert(threshold)
                    // On a cold start (no previous reading) don't announce
                    // thresholds retroactively — just arm them, or launching
                    // the app at 90% would fire every configured threshold
                    // at once.
                    if previous != nil {
                        alerts.append(.crossedThreshold(
                            percent: threshold,
                            metric: metric.label,
                            current: metric.percent
                        ))
                    }
                } else if !crossed {
                    fired.remove(threshold)
                }
            }

            firedThresholds[metric.key] = fired
        }

        record(snapshot)
        return alerts
    }

    private mutating func record(_ snapshot: UsageSnapshot) {
        guard snapshot.hasData else { return }
        lastPercent["session"] = snapshot.sessionPercent
        lastPercent["weekly"] = snapshot.weeklyPercent
    }
}
