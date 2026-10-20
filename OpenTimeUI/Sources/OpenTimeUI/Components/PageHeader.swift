import SwiftUI

public struct PageHeader: View {
    public let title: String
    public let meta: String?

    public init(title: String, meta: String? = nil) {
        self.title = title
        self.meta = meta
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text(title.uppercased())
                    .font(Theme.Font.display(size: 22, weight: .bold))
                    .kerning(-0.22)
                    .foregroundStyle(Theme.fg)

                Spacer()

                if let meta {
                    Text(meta.uppercased())
                        .font(Theme.Font.display(size: 10, weight: .regular))
                        .kerning(1.8)
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.bottom, 6)

            Rectangle()
                .fill(Theme.rule)
                .frame(height: 4)
        }
        .padding(.bottom, 14)
    }
}

#Preview("Light") {
    FontRegistration.registerNHG()
    return PageHeader(title: "Availability", meta: "Fri 9 May")
        .padding(20)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    FontRegistration.registerNHG()
    return PageHeader(title: "Availability", meta: "Fri 9 May")
        .padding(20)
        .preferredColorScheme(.dark)
        .background(Theme.bg)
}
