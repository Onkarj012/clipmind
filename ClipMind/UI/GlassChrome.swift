import SwiftUI

extension View {
    func clipMindGlass(in shape: some InsettableShape = RoundedRectangle(cornerRadius: 14, style: .continuous)) -> some View {
        background {
            shape
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
    }
}
