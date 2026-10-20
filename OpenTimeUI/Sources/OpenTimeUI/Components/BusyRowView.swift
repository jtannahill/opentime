import SwiftUI

public struct BusyRowView: View {
    public let timeRange: String
    public let title: String

    public init(timeRange: String, title: String) {
        self.timeRange = timeRange
        self.title = title
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(timeRange)
                .font(Theme.Font.display(size: 13, weight: .medium))
                .tnum()
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 130, alignment: .leading)

            Text(title)
                .font(Theme.Font.display(size: 13, weight: .medium))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
