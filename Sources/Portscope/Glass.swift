import SwiftUI

extension View {
    /// Liquid Glass on macOS 26+, a regular material everywhere else (and on older SDKs).
    @ViewBuilder
    func panelGlass(cornerRadius: CGFloat = 16) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
        #else
        self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        #endif
    }
}
