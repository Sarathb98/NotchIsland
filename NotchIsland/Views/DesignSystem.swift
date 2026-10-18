import SwiftUI

/// Shared metrics describe the interface, never the physical display notch.
enum DesignSystem {
    static let compactSpacing: CGFloat = 6
    static let spacing: CGFloat = 12
    static let contentPadding: CGFloat = 16
    static let surfaceRadius: CGFloat = 12
    static let islandRadius: CGFloat = 22
    static let controlSize: CGFloat = 28
    static let accent = Color.accentColor
}

private struct IslandSurface: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if reduceTransparency || contrast == .increased {
                content.background(Color(nsColor: .controlBackgroundColor), in: shape)
            } else if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
            }
        }
        .overlay {
            if contrast == .increased {
                shape.strokeBorder(.primary.opacity(0.65), lineWidth: 1)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func islandSurface(cornerRadius: CGFloat = DesignSystem.surfaceRadius) -> some View {
        modifier(IslandSurface(cornerRadius: cornerRadius))
    }
}

struct IslandTabStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 11).frame(height: 26)
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.48))
            .background(.white.opacity(configuration.isPressed ? 0.24 : selected ? 0.14 : 0), in: Capsule())
            .contentShape(Capsule())
    }
}

struct IslandIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 24, height: 26)
            .background(.white.opacity(configuration.isPressed ? 0.16 : 0), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
    }
}
