import SwiftUI

struct SentenceTranslationView: View {
    let originalText: String
    let result: SentenceTranslationResult
    let inputType: InputType

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 原文（灰色小字）
            Text(originalText)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)

            // 译文（主文字）
            Text(result.translation)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            // 语法/用法解析
            if let analysis = result.analysis, !analysis.isEmpty {
                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 12))
                        Text(inputType.analysisTitle)
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(.secondary)

                    Text(analysis)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }

            Divider()
                .padding(.vertical, 2)

            // 操作栏
            HStack(spacing: 12) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.translation, forType: .string)
                } label: {
                    Label("复制译文", systemImage: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
    }
}
