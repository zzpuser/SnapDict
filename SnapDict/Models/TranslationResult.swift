import Foundation

struct TranslationResult: Codable, Sendable {
    let word: String
    let phonetic: String
    let translation: String
    var examples: [String]
    let correctedFrom: String?
    var etymology: String?
    var association: String?

    enum CodingKeys: String, CodingKey {
        case word, phonetic, translation, examples, etymology, association
        case correctedFrom = "corrected_from"
    }
}
