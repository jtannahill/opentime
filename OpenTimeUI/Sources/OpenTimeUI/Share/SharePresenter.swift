#if canImport(UIKit)
import UIKit

/// Opens the system share sheet straight away, from a plain button, so a
/// share needs no sheet of our own in front of it.
@MainActor
public enum SharePresenter {
    public static func present(_ items: [Any]) {
        guard let top = topViewController() else { return }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad shows the sheet as a popover, which needs somewhere to point.
        if let pop = vc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.maxX - 60, y: top.view.safeAreaInsets.top, width: 1, height: 1)
            pop.permittedArrowDirections = .up
        }
        top.present(vc, animated: true)
    }

    /// The view controller at the front of the active window, to present from.
    static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController else { return nil }
        var top = root
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}
#endif
