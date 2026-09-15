import SwiftUI

extension View {
    /// Native circular controls share an explicit control size and a bright tint,
    /// with black symbols in both appearances. Layout still belongs to the toolbar.
    func instaDictCircleButton() -> some View {
        self.buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .imageScale(.large)
            .tint(Color(red: 0.69, green: 0.886, blue: 0.702))
            .foregroundStyle(.black)
    }
}
