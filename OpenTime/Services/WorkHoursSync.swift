// OpenTime/Services/WorkHoursSync.swift
import Foundation
import OpenTimeUI
import WatchConnectivity

/// Pushes the work-hours pair to the watch.
///
/// `applicationContext` rather than `transferUserInfo`: it is
/// latest-state-wins, so rapid edits in the picker do not queue stale
/// values, and the system retains the most recent context and delivers it
/// when the watch app next activates. A watch that was off or not running
/// at edit time therefore catches up on its own with no handshake.
///
/// If a context never arrives the watch reads its empty defaults and gets
/// the 9-17 default, which is the same fail-safe as everywhere else.
final class WorkHoursSync: NSObject {
    static let shared = WorkHoursSync()

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Sends the currently stored window. Safe to call before activation
    /// completes; the send is skipped and the next call will carry it.
    func push() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            // A prior activation may have failed, or activate() may not have
            // run yet. Set the delegate before asking again so the completion
            // callback is received no matter the call order; the delegate's
            // success path performs the catch-up send.
            session.delegate = self
            session.activate()
            return
        }
        let hours = WorkHours.current()
        try? session.updateApplicationContext(
            WorkHoursPayload.encode(start: hours.start, end: hours.end)
        )
    }
}

extension WorkHoursSync: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Send the current window as soon as the session is usable so a
        // watch that missed earlier edits is brought up to date.
        guard activationState == .activated else { return }
        push()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Required on iOS for watch switching; reactivate for the new watch.
        session.activate()
    }
}
