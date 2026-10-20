import Combine
import SwiftUI
import OpenTimeUI

@main
struct OpenTimeApp: App {
    @StateObject private var deepLink = DeepLinkRouter()

    init() {
        FontRegistration.registerNHG()
        WorkHoursSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deepLink)
                .onOpenURL { deepLink.handle($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { deepLink.handle(url) }
                }
                #if DEBUG
                // -openURL <url>: route a link without a real invocation, for the simulator.
                .task {
                    if let i = CommandLine.arguments.firstIndex(of: "-openURL"), i + 1 < CommandLine.arguments.count,
                       let url = URL(string: CommandLine.arguments[i + 1]) {
                        deepLink.handle(url)
                    }
                }
                #endif
        }
    }
}

/// Routes `opentime://slot?start=<unix>&end=<unix>` URLs (typically
/// from widget chip taps) into the running app. ContentView observes
/// `pendingSlot` and scrolls + highlights the matching day.
final class DeepLinkRouter: ObservableObject {
    struct PendingSlot: Equatable {
        let start: Date
        let end: Date
    }

    @Published var pendingSlot: PendingSlot?
    /// A pick-a-time link opened while the full app is installed.
    @Published var incomingPick: IncomingPick?

    /// A reply to one of our pick-a-time links, with the times they chose.
    @Published var incomingReply: IncomingReply?

    struct IncomingPick: Identifiable {
        let id = UUID()
        let link: PickLink?
    }

    struct IncomingReply: Identifiable {
        let id = UUID()
        let reply: PickReply?
    }

    func handle(_ url: URL) {
        if url.host == PickLink.host || url.host == "www.\(PickLink.host)" {
            if url.path.hasPrefix(PickReply.path) {
                incomingReply = IncomingReply(reply: PickReply(url: url))
            } else {
                incomingPick = IncomingPick(link: PickLink(url: url))
            }
            return
        }
        guard url.scheme == "opentime", url.host == "slot",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let startStr = comps.queryItems?.first(where: { $0.name == "start" })?.value,
              let endStr = comps.queryItems?.first(where: { $0.name == "end" })?.value,
              let startUnix = TimeInterval(startStr),
              let endUnix = TimeInterval(endStr)
        else { return }
        pendingSlot = PendingSlot(
            start: Date(timeIntervalSince1970: startUnix),
            end: Date(timeIntervalSince1970: endUnix)
        )
    }
}
