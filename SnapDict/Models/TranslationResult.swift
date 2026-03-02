import Foundation

struct TranslationResult: Codable, Sendable {
    let word: String
    let phonetic: String
    let translation: String
    var examples: [String]
    var originalInput: String?
    var suggestedCorrection: String?
    var etymology: String?
    var association: String?

    enum CodingKeys: String, CodingKey {
        case word, phonetic, translation, examples, etymology, association
        case originalInput = "original_input"
        case suggestedCorrection = "suggested_correction"
    }
}
