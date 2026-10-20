import SwiftUI
import EventKit
import EventKitUI

struct EventEditSheet: UIViewControllerRepresentable {
    let store: EKEventStore
    let start: Date
    let end: Date
    let onSaved: () -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSaved: onSaved, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = store
        let event = EKEvent(eventStore: store)
        event.startDate = start
        event.endDate = end
        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onSaved: () -> Void
        let onDismiss: () -> Void

        init(onSaved: @escaping () -> Void, onDismiss: @escaping () -> Void) {
            self.onSaved = onSaved
            self.onDismiss = onDismiss
        }

        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            if action == .saved {
                onSaved()
            }
            onDismiss()
        }
    }
}
