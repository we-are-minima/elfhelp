import SwiftUI
import UIKit

struct SharedTravesura: Identifiable {
    let id = UUID()
    let image: UIImage?
    let message: String
}

struct TravesuraShareSheet: UIViewControllerRepresentable {
    let payload: SharedTravesura
    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = []
        if let image = payload.image { items.append(image) }
        items.append(payload.message)
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
