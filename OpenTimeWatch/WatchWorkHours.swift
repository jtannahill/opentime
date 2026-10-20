// OpenTimeWatch/WatchWorkHours.swift
import Foundation
import WatchConnectivity

/// Watch-local copy of the work-hours setting.
///
/// App Group defaults do not cross from the iPhone to the watch, so the
/// phone pushes the pair over WatchConnectivity and this type stores it in
/// the watch's own standard defaults. Duplicated rather than shared
/// because OpenTimeUI is not linked to the watch target, the same reason
/// WatchAvailabilityEngine exists. Keys and default must stay identical to
/// OpenTimeUI's WorkHours.
enum WatchWorkHours {
    static let defaultStart = 9
    static let defaultEnd = 17
    static let startKey = "workStartHour"
    static let endKey = "workEndHour"

    /// Posted after a new window arrives so the UI can refresh.
    static let didChange = Notification.Name("WatchWorkHoursDidChange")

    static func current(defaults: UserDefaults = .standard) -> (start: Int, end: Int) {
        sanitize(
            start: defaults.object(forKey: startKey) as? Int,
            end: defaults.object(forKey: endKey) as? Int
        )
    }

    static func store(_ context: [String: Any], defaults: UserDefaults = .standard) {
        let clean = sanitize(
            start: context[startKey] as? Int,
            end: context[endKey] as? Int
        )
        defaults.set(clean.start, forKey: startKey)
        defaults.set(clean.end, forKey: endKey)
    }

    static func sanitize(start: Int?, end: Int?) -> (start: Int, end: Int) {
        guard let start, let end,
              (0...23).contains(start),
              (0...23).contains(end),
              start < end
        else { return (defaultStart, defaultEnd) }
        return (start, end)
    }
}

/// Receives the phone's application context.
final class WatchWorkHoursSync: NSObject {
    static let shared = WatchWorkHoursSync()

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }
}

extension WatchWorkHoursSync: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // The system retains the phone's most recent context, so an edit
        // made while this app was not running is available right here.
        guard activationState == .activated else { return }
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return }
        apply(context)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    private func apply(_ context: [String: Any]) {
        WatchWorkHours.store(context)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: WatchWorkHours.didChange, object: nil)
        }
    }
}
