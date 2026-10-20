import StoreKit
import SwiftUI
import OpenTimeUI

/// Opens from a pick-a-time link (lulls.app/pick#...) and shows the
/// sender's free times. Everything it needs is in the link itself.
@main
struct OpenTimeClipApp: App {
    @State private var link: PickLink?
    @State private var opened = false

    init() {
        FontRegistration.registerNHG()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if opened {
                    PickTimeView(link: link, footer: AnyView(GetAppFooter()))
                } else {
                    Color.clear
                }
            }
            .background(Theme.bg)
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                open(activity.webpageURL)
            }
            .onOpenURL { open($0) }
            .task {
                #if DEBUG
                // -pickLink <url>: open a link without a real invocation, for the simulator.
                if let i = CommandLine.arguments.firstIndex(of: "-pickLink"), i + 1 < CommandLine.arguments.count {
                    open(URL(string: CommandLine.arguments[i + 1]))
                }
                #endif
                // A launch with no link (say, from the App Clip card's Open
                // with nothing attached) still shows the explanation.
                try? await Task.sleep(for: .milliseconds(600))
                opened = true
            }
        }
    }

    private func open(_ url: URL?) {
        link = url.flatMap(PickLink.init(url:))
        opened = true
    }
}

/// The one place the clip mentions the full app.
private struct GetAppFooter: View {
    @State private var showOverlay = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Share your own free times the same way with Open Time.")
                .font(Theme.Font.display(size: 13, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
            Button("GET OPEN TIME") { showOverlay = true }
                .font(Theme.Font.display(size: 11, weight: .bold, relativeTo: .footnote))
                .kerning(1.4)
                .foregroundStyle(Theme.fg)
                .frame(minHeight: 44)
        }
        .appStoreOverlay(isPresented: $showOverlay) {
            SKOverlay.AppClipConfiguration(position: .bottom)
        }
    }
}
