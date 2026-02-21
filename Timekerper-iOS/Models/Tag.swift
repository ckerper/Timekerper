import Foundation

struct Tag: Codable, Identifiable, Equatable, Sendable {
    var id: Int
    var name: String
    var color: String   // "#RRGGBB"
}
