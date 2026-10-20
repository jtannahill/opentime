import UIKit
import Messages
import SwiftUI
import OpenTimeUI

class MessagesViewController: MSMessagesAppViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        FontRegistration.registerNHG()
        showComposeView()
    }

    override func willBecomeActive(with conversation: MSConversation) {
        showComposeView()
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        showComposeView()
    }

    private func showComposeView() {
        for child in children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }

        let view = AvailabilityPicker(
            isCompact: presentationStyle == .compact,
            onExpand: { [weak self] in
                self?.requestPresentationStyle(.expanded)
            },
            onSend: { [weak self] text in
                self?.sendAvailability(text)
            }
        )

        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.frame = self.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func sendAvailability(_ text: String) {
        activeConversation?.insertText(text) { [weak self] _ in
            self?.requestPresentationStyle(.compact)
        }
    }
}
