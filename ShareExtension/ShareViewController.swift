import UIKit
import SwiftUI
import OpenTimeUI

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        FontRegistration.registerNHG()

        let picker = SharePickerView(
            onDone: { [weak self] text in
                UIPasteboard.general.string = text
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: NSError(domain: "com.jamestannahill.CalendarAvailability.ShareExtension", code: 0))
            }
        )

        let host = UIHostingController(rootView: picker)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
