import SwiftUI

public struct QueryBarView: View {

    public static let exampleQueries: [String] = [
        "WHEN AM I FREE?",
        "ANY HOUR FRIDAY AFTERNOON",
        "30 MIN TOMORROW MORNING",
        "NEXT TUESDAY AFTER 2PM",
        "COFFEE NEXT WEEK",
        "ANY 2-HOUR BLOCK"
    ]

    @Binding public var text: String
    public var isLoading: Bool
    public var hasResult: Bool
    public var onSubmit: () async -> Void
    public var onClear: () -> Void

    @FocusState private var focused: Bool
    private let chips: [String]

    public init(
        text: Binding<String>,
        isLoading: Bool,
        hasResult: Bool,
        onSubmit: @escaping () async -> Void,
        onClear: @escaping () -> Void
    ) {
        self._text = text
        self.isLoading = isLoading
        self.hasResult = hasResult
        self.onSubmit = onSubmit
        self.onClear = onClear
        // Shuffle once per view-creation so chips are stable for a session.
        self.chips = Array(Self.exampleQueries.dropFirst().shuffled().prefix(3))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            barRow
            Rectangle().fill(Theme.fg).frame(height: 1)
            if showChips {
                chipRow
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
        }
    }

    private var showChips: Bool { text.isEmpty && !hasResult }

    private var barRow: some View {
        HStack(spacing: 8) {
            Text("ASK")
                .font(Theme.Font.display(size: 10, weight: .bold))
                .kerning(1.8)
                .foregroundStyle(Theme.muted)

            TimelineView(.periodic(from: .now, by: 4.0)) { ctx in
                placeholderField(at: ctx.date)
            }

            if isLoading {
                ProgressView().controlSize(.small)
            } else if !text.isEmpty || hasResult {
                Button {
                    onClear()
                    focused = false
                } label: {
                    Text("× CLEAR")
                        .font(Theme.Font.display(size: 10, weight: .bold))
                        .kerning(1.8)
                        .foregroundStyle(Theme.fg)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear query")
            }
        }
        .padding(.vertical, 6)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Button {
                        text = chip
                        Task { await onSubmit() }
                    } label: {
                        Text(chip)
                            .font(Theme.Font.display(size: 10, weight: .bold))
                            .kerning(1.4)
                            .foregroundStyle(Theme.fg)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .overlay(Rectangle().stroke(Theme.fg, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Returns the placeholder index to render at `date`. Stops rotating
    /// when the field is focused OR has any text.
    private func placeholderIdx(at date: Date) -> Int {
        if focused || !text.isEmpty { return 0 }
        let sec = Int(date.timeIntervalSinceReferenceDate)
        return (sec / 4) % Self.exampleQueries.count
    }

    @ViewBuilder
    private func placeholderField(at date: Date) -> some View {
        let idx = placeholderIdx(at: date)
        #if os(iOS)
        TextField(Self.exampleQueries[idx], text: $text)
            .focused($focused)
            .textFieldStyle(.plain)
            .font(Theme.Font.display(size: 13, weight: .regular))
            .foregroundStyle(Theme.fg)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit { Task { await onSubmit() } }
        #else
        TextField(Self.exampleQueries[idx], text: $text)
            .focused($focused)
            .textFieldStyle(.plain)
            .font(Theme.Font.display(size: 13, weight: .regular))
            .foregroundStyle(Theme.fg)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .onSubmit { Task { await onSubmit() } }
        #endif
    }
}

#Preview("Empty, Light") {
    FontRegistration.registerNHG()
    return QueryBarView(
        text: .constant(""),
        isLoading: false,
        hasResult: false,
        onSubmit: {},
        onClear: {}
    )
    .padding(20)
    .preferredColorScheme(.light)
}

#Preview("With text, Dark") {
    FontRegistration.registerNHG()
    return QueryBarView(
        text: .constant("next tuesday after 2pm"),
        isLoading: false,
        hasResult: true,
        onSubmit: {},
        onClear: {}
    )
    .padding(20)
    .background(Theme.bg)
    .preferredColorScheme(.dark)
}
