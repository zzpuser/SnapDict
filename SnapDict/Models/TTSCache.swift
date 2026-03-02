import Foundation
import SwiftData

@Model
final class TTSCache {
    @Attribute(.unique) var word: String
    @Attribute(.externalStorage) var audioData: Data
    var createdAt: Date

    init(word: String, audioData: Data, createdAt: Date = .now) {
        self.word = word
        self.audioData = audioData
        self.createdAt = createdAt
    }
}
