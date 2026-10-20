import SwiftUI

public struct MTSquareButton: View {
    public let label: String
    public let isSelected: Bool
    public let role: Role
    public let action: () -> Void

    public enum Role { case neutral, submit }

    public init(
        _ label: String,
        isSelected: Bool = false,
        role: Role = .neutral,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.isSelected = isSelected
        self.role = role
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(Theme.Font.display(size: 10, weight: .bold))
                .kerning(1.8)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .foregroundStyle(foregroundColor)
                .background(backgroundColor)
                .overlay(
                    Rectangle().stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.linear(duration: 0.12), value: isSelected)
    }

    private var foregroundColor: Color {
        switch role {
        case .submit:  return Theme.bg
        case .neutral: return isSelected ? Theme.bg : Theme.fg
        }
    }
    private var backgroundColor: Color {
        switch role {
        case .submit:  return Theme.accent
        case .neutral: return isSelected ? Theme.fg : Theme.bg
        }
    }
    private var borderColor: Color {
        switch role {
        case .submit:  return Theme.accent
        case .neutral: return Theme.fg
        }
    }
}

#Preview("Light") {
    FontRegistration.registerNHG()
    return VStack(spacing: 12) {
        MTSquareButton("15") {}
        MTSquareButton("30", isSelected: true) {}
        MTSquareButton("Send", role: .submit) {}
    }
    .padding(20)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    FontRegistration.registerNHG()
    return VStack(spacing: 12) {
        MTSquareButton("15") {}
        MTSquareButton("30", isSelected: true) {}
        MTSquareButton("Send", role: .submit) {}
    }
    .padding(20)
    .background(Theme.bg)
    .preferredColorScheme(.dark)
}
