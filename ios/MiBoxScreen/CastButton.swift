import GoogleCast
import SwiftUI

struct CastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
        let button = GCKUICastButton(frame: .zero)
        button.tintColor = .systemBlue
        return button
    }

    func updateUIView(_ uiView: GCKUICastButton, context: Context) {}
}
