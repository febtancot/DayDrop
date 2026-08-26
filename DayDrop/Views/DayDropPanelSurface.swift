import SwiftUI

/// Keeps DayDrop's menu-bar content legible when macOS uses a highly
/// translucent window material. `windowBackgroundColor` follows the current
/// appearance but remains opaque, so light text is not placed directly over a
/// bright desktop image (and vice versa).
private struct DayDropPanelSurfaceModifier: ViewModifier {
    private let backgroundColor = Color(nsColor: .windowBackgroundColor)

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .background(backgroundColor)
                .containerBackground(backgroundColor, for: .window)
        } else {
            content
                .background(backgroundColor)
        }
    }
}

extension View {
    func dayDropPanelSurface() -> some View {
        modifier(DayDropPanelSurfaceModifier())
    }
}
