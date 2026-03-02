import Foundation
import SwiftData

@Model
final class TranslationCache {
    @Attribute(.unique) var word: String
    var jsonData: String
    var createdAt: Date

    init(word: String, jsonData: String, createdAt: Date = .now) {
        self.word = word
        self.jsonData = jsonData
        self.createdAt = createdAt
    }
}
