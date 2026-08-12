import SwiftUI

/// A compact switch tuned for DayDrop's small menu-bar surfaces.
///
/// The native macOS switch remains intentionally prominent even at the small
/// control size. This style keeps the same toggle behavior while using a
/// quieter track, a smaller thumb, and a softer selected color.
struct DayDropCompactToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label

            Spacer(minLength: 12)

            ZStack {
                Capsule(style: .continuous)
                    .fill(trackColor(isOn: configuration.isOn))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }

                Circle()
                    .fill(Color.white.opacity(0.97))
                    .frame(width: 12, height: 12)
                    .shadow(
                        color: Color.black.opacity(0.12),
                        radius: 1,
                        y: 0.5
                    )
                    .offset(x: configuration.isOn ? 7 : -7)
            }
            .frame(width: 30, height: 16)
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                configuration.isOn.toggle()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
    }

    private func trackColor(isOn: Bool) -> Color {
        if isOn {
            return Color(nsColor: .systemBlue).opacity(0.68)
        }
        return Color.secondary.opacity(0.16)
    }
}
