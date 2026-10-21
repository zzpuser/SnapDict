import Foundation

enum InputType {
    case word       // 英文单词/短词组 → 走词典流水线
    case sentence   // 英文短句/片段 → 走翻译流水线
    case chinese    // 纯中文输入（不含英文字母）→ 中译英
    case mixed      // 中英混合 → 由模型判断主体语言决定翻译方向

    /// 解析区标题
    var analysisTitle: String {
        switch self {
        case .chinese: "用法说明"
        case .mixed: "解析"
        case .word, .sentence: "语法解析"
        }
    }
}

enum InputClassifier {
    static func classify(_ text: String) -> InputType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .word }

        if trimmed.unicodeScalars.contains(where: { isCJK($0) }) {
            // 夹杂英文字母时无法按字符判断翻译方向（如英文句子里的中文人名），交给模型判断主体语言
            let hasLatin = trimmed.unicodeScalars.contains { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }
            return hasLatin ? .mixed : .chinese
        }

        // 多行文本走翻译流水线（保留换行），不按单词查询
        if trimmed.contains(where: \.isNewline) {
            return .sentence
        }

        let wordCount = trimmed.split(separator: " ").count
        if wordCount <= 2 && trimmed.count <= 25 {
            return .word
        }

        return .sentence
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) ||
        (0x3400...0x4DBF).contains(scalar.value) ||
        (0x20000...0x2A6DF).contains(scalar.value) ||
        (0xF900...0xFAFF).contains(scalar.value)
    }
}
