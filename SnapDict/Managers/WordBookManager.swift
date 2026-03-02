import Foundation
import SwiftData

@MainActor
@Observable
final class WordBookManager {
    static let shared = WordBookManager()

    var modelContainer: ModelContainer?

    private init() {}

    func setup(container: ModelContainer) {
        self.modelContainer = container
    }

    @discardableResult
    func saveWord(from result: TranslationResult) throws -> WordEntry {
        guard let container = modelContainer else {
            throw WordBookError.noContainer
        }
        let context = container.mainContext

        let descriptor = FetchDescriptor<WordEntry>(
            predicate: #Predicate { $0.word == result.word }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.phonetic = result.phonetic
            existing.translation = result.translation
            existing.examples = result.examples
            try context.save()
            return existing
        }

        let entry = WordEntry(
            word: result.word,
            phonetic: result.phonetic,
            translation: result.translation,
            examples: result.examples
        )
        context.insert(entry)
        try context.save()
        return entry
    }

    func deleteWord(_ entry: WordEntry) throws {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        context.delete(entry)
        try context.save()
    }

    func deleteWord(byName word: String) throws {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        let descriptor = FetchDescriptor<WordEntry>(
            predicate: #Predicate { $0.word == word }
        )
        if let entry = try context.fetch(descriptor).first {
            context.delete(entry)
            try context.save()
        }
    }

    func toggleMastered(_ entry: WordEntry) throws {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        entry.isMastered.toggle()
        try context.save()
    }

    func isWordSaved(_ word: String) -> Bool {
        guard let container = modelContainer else { return false }
        let context = container.mainContext
        let descriptor = FetchDescriptor<WordEntry>(
            predicate: #Predicate { $0.word == word }
        )
        return (try? context.fetchCount(descriptor)) ?? 0 > 0
    }

    func wordCount() -> Int {
        guard let container = modelContainer else { return 0 }
        let context = container.mainContext
        let descriptor = FetchDescriptor<WordEntry>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    func nextWordForPush() -> WordEntry? {
        guard let container = modelContainer else { return nil }
        let context = container.mainContext
        let pushOnlyLearning = UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.pushOnlyLearning) as? Bool
            ?? Constants.Defaults.pushOnlyLearning
        var descriptor: FetchDescriptor<WordEntry>
        if pushOnlyLearning {
            descriptor = FetchDescriptor<WordEntry>(
                predicate: #Predicate { !$0.isMastered },
                sortBy: [SortDescriptor(\.pushCount), SortDescriptor(\.createdAt)]
            )
        } else {
            descriptor = FetchDescriptor<WordEntry>(
                sortBy: [SortDescriptor(\.pushCount), SortDescriptor(\.createdAt)]
            )
        }
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func markPushed(_ entry: WordEntry) throws {
        guard let container = modelContainer else { return }
        let context = container.mainContext
        entry.lastPushedAt = .now
        entry.pushCount += 1
        try context.save()
    }
}

enum WordBookError: LocalizedError {
    case noContainer

    var errorDescription: String? {
        switch self {
        case .noContainer: "数据库未初始化"
        }
    }
}
