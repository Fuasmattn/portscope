import SwiftUI

/// Compact capsule button that brightens on hover and dims while pressed.
struct PillButtonStyle: ButtonStyle {
    enum Role { case neutral, destructive }
    var role: Role

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, role: role)
    }

    private struct Pill: View {
        let configuration: Configuration
        let role: Role
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(role == .destructive ? Color.white : Color.primary)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(role == .neutral ? (hovering ? 0.3 : 0.18) : 0)))
                .opacity(configuration.isPressed ? 0.7 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }

        private var fill: Color {
            switch role {
            case .destructive: return Color.red.opacity(hovering ? 1 : 0.85)
            case .neutral: return Color.primary.opacity(hovering ? 0.18 : 0.08)
            }
        }
    }
}

/// Borderless icon button with a soft circular hover fill. `onDark` tunes it for the radar card.
struct IconButtonStyle: ButtonStyle {
    var onDark = false
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        Icon(configuration: configuration, onDark: onDark, active: active)
    }

    private struct Icon: View {
        let configuration: Configuration
        let onDark: Bool
        let active: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.body)
                .foregroundStyle(foreground)
                .frame(width: 24, height: 24)
                .background(Circle().fill(base.opacity(hovering ? 0.16 : (active ? 0.1 : 0))))
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Circle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var base: Color { onDark ? .white : .primary }

        private var foreground: Color {
            if active { return base }
            return base.opacity(hovering ? 1 : (onDark ? 0.8 : 0.65))
        }
    }
}

/// Half-point divider at 8 % so rows read as one surface, not a table.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
    }
}
