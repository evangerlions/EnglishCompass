import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(enabled ? Color.white : Color.secondary)
            .background(enabled ? Color(red: 0.08, green: 0.43, blue: 0.40) : Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
