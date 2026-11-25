import Foundation

/// Campaigns remain disabled until dates, copy, image and destination are approved.
struct AppPromotion: Decodable, Identifiable {
    let id: String
    let enabled: Bool
    let days: [Int]
    let title: String
    let message: String
    let imageURL: URL
    let buttonTitle: String
    let destinationURL: URL

    static let configured: [AppPromotion] = {
        guard let url = Bundle.main.url(forResource: "Promotions", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return ((try? JSONDecoder().decode([AppPromotion].self, from: data)) ?? []).filter {
            $0.destinationURL.scheme == "https" && $0.imageURL.scheme == "https"
                && $0.days.allSatisfy { (1...24).contains($0) }
        }
    }()
}
