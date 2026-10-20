#if canImport(EventKitUI)
import SwiftUI
import EventKit
import EventKitUI

/// The system new-event sheet, filled in with a confirmed time. The person
/// adds invitees there, and their own calendar account sends the invitation.
/// Since iOS 17 this sheet runs without calendar access.
struct EventEditSheet: UIViewControllerRepresentable {
    let title: String
    let start: Date
    let end: Date
    /// Called once with true if the event was added.
    let onDone: (Bool) -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        let vc = EKEventEditViewController()
        vc.eventStore = store
        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: (Bool) -> Void
        init(onDone: @escaping (Bool) -> Void) { self.onDone = onDone }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone(action == .saved)
        }
    }
}
#endif
