import SwiftUI

enum WordCardRenderer {
    @MainActor
    static func render(word: String, phonetic: String, translation: String) -> Data? {
        let view = WordCardImageView(word: word, phonetic: phonetic, translation: translation)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0 // 墨水屏不需要 Retina
        guard let cgImage = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
