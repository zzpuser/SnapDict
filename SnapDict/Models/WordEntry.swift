import Foundation
import SwiftData

@Model
final class WordEntry {
    @Attribute(.unique) var word: String
    var phonetic: String
    var translation: String
    var examples: [String]
    var createdAt: Date
    var lastPushedAt: Date?
    var pushCount: Int
    var isMastered: Bool

    init(
        word: String,
        phonetic: String = "",
        translation: String = "",
        examples: [String] = [],
        createdAt: Date = .now,
        lastPushedAt: Date? = nil,
        pushCount: Int = 0,
        isMastered: Bool = false
    ) {
        self.word = word
        self.phonetic = phonetic
        self.translation = translation
        self.examples = examples
        self.createdAt = createdAt
        self.lastPushedAt = lastPushedAt
        self.pushCount = pushCount
        self.isMastered = isMastered
    }
}
