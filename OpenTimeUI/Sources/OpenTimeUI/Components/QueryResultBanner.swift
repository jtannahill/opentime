import SwiftUI

public struct QueryResultBanner: View {

    public enum State {
        /// Filter returned matches. `summary` is from AvailabilityIntent.summary(now:).
        case match(summary: String, slotCount: Int)
        /// Filter returned empty but a suggestion was found.
        case suggestion(summary: String, suggestionText: String, onTap: () -> Void)
        /// Filter returned empty AND no suggestion was found.
        case noMatch(summary: String)
        /// Parser threw.
        case error
    }

    public let state: State

    public init(state: State) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch state {
            case .match(let summary, let count):
                label("INTERPRETED: \(summary)  ·  \(count) SLOT\(count == 1 ? "" : "S")", tint: Theme.accent)
            case .suggestion(let summary, let suggestionText, let onTap):
                label("NO MATCH: \(summary)", tint: Theme.muted)
                Button(action: onTap) {
                    label("EARLIEST: \(suggestionText) →", tint: Theme.accent)
                }
                .buttonStyle(.plain)
            case .noMatch(let summary):
                label("NO MATCHES: \(summary). TRY A WIDER WINDOW.", tint: Theme.muted)
            case .error:
                label("COULDN'T READ THAT QUERY — TRY REPHRASING", tint: Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func label(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Theme.Font.display(size: 10, weight: .bold))
            .kerning(1.8)
            .foregroundStyle(tint)
    }
}

#Preview("Match") {
    FontRegistration.registerNHG()
    return QueryResultBanner(state: .match(summary: "TUE MAY 12 · AFTER 2PM · 60 MIN", slotCount: 3))
        .padding(20)
        .preferredColorScheme(.light)
}

#Preview("Suggestion") {
    FontRegistration.registerNHG()
    return QueryResultBanner(state: .suggestion(
        summary: "TUE MAY 12 · AFTER 2PM · 60 MIN",
        suggestionText: "WED 1–2 PM (DATE RELAXED)",
        onTap: {}
    ))
    .padding(20)
    .preferredColorScheme(.light)
}

#Preview("Error") {
    FontRegistration.registerNHG()
    return QueryResultBanner(state: .error)
        .padding(20)
        .preferredColorScheme(.dark)
        .background(Theme.bg)
}
