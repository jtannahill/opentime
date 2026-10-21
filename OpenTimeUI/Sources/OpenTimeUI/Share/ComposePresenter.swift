#if canImport(MessageUI)
import MessageUI
import UIKit

/// Opens a new message or email already addressed and written, inside the
/// app, so sending it is one tap. Where the device cannot send from here, it
/// opens Messages or Mail instead, and failing that the share sheet.
@MainActor
public enum ComposePresenter {
    private static let delegate = Delegate()

    /// `sent` runs once the message has gone (or, for Mail, been queued).
    public static func present(to: PickLink.ReplyTo, body: String, subject: String,
                               sent: @escaping @MainActor () -> Void = {}) {
        guard let top = SharePresenter.topViewController() else { return }
        delegate.sent = sent
        switch to {
        case .phone(let number) where MFMessageComposeViewController.canSendText():
            let vc = MFMessageComposeViewController()
            vc.recipients = [number]
            vc.body = body
            vc.messageComposeDelegate = delegate
            top.present(vc, animated: true)
        case .email(let address) where MFMailComposeViewController.canSendMail():
            let vc = MFMailComposeViewController()
            vc.setToRecipients([address])
            vc.setSubject(subject)
            vc.setMessageBody(body, isHTML: false)
            vc.mailComposeDelegate = delegate
            top.present(vc, animated: true)
        default:
            guard let url = to.url(body: body, subject: subject) else {
                SharePresenter.present([body])
                return
            }
            UIApplication.shared.open(url) { opened in
                if !opened { SharePresenter.present([body]) }
            }
        }
    }

    @MainActor fileprivate final class Delegate: NSObject {
        var sent: @MainActor () -> Void = {}
    }
}

extension ComposePresenter.Delegate: @preconcurrency MFMessageComposeViewControllerDelegate {
    func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                      didFinishWith result: MessageComposeResult) {
        if result == .sent { sent() }
        controller.dismiss(animated: true)
    }
}

extension ComposePresenter.Delegate: @preconcurrency MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController,
                               didFinishWith result: MFMailComposeResult, error: Error?) {
        if result == .sent { sent() }
        controller.dismiss(animated: true)
    }
}
#endif
