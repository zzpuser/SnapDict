import SwiftUI
import SwiftData

struct PanelWordBookView: View {
    @Query(sort: \WordEntry.createdAt, order: .reverse) private var words: [WordEntry]
    @State private var searchText = ""
    @State private var filter: WordFilter = .learning
    @State private var selectedEntry: WordEntry?
    @State private var sortByAlpha = false

    private var stats: (total: Int, mastered: Int, learning: Int) {
        let total = words.count
        let mastered = words.filter(\.isMastered).count
        return (total, mastered, total - mastered)
    }

    private var filteredWords: [WordEntry] {
        var result = words

        switch filter {
        case .learning: result = result.filter { !$0.isMastered }
        case .mastered: result = result.filter(\.isMastered)
        case .all: break
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.word.lowercased().contains(query) ||
                $0.translation.lowercased().contains(query)
            }
        }

        if sortByAlpha {
            result = result.sorted { $0.word.lowercased() < $1.word.lowercased() }
        }

        return result
    }

    private func countForFilter(_ f: WordFilter) -> Int {
        switch f {
        case .all: return stats.total
        case .learning: return stats.learning
        case .mastered: return stats.mastered
        }
    }

    var body: some View {
        let currentWords = filteredWords
        VStack(spacing: 0) {
            // 工具栏
            compactToolbar

            Divider()

            // 内容区
            if currentWords.isEmpty {
                ContentUnavailableView {
                    Label(
                        searchText.isEmpty ? "暂无生词" : "未找到匹配结果",
                        systemImage: searchText.isEmpty ? "books.vertical" : "magnifyingglass"
                    )
                } description: {
                    Text(searchText.isEmpty
                         ? (filter == .all ? "翻译时点击书签图标保存生词" : "当前分类下暂无单词")
                         : "试试其他关键词")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(currentWords) { entry in
                            CompactWordRow(
                                entry: entry,
                                isSelected: selectedEntry?.id == entry.id,
                                onTap: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                        if selectedEntry?.id == entry.id {
                                            selectedEntry = nil
                                        } else {
                                            selectedEntry = entry
                                        }
                                    }
                                },
                                onDelete: {
                                    if selectedEntry?.id == entry.id { selectedEntry = nil }
                                    try? WordBookManager.shared.deleteWord(entry)
                                },
                                onToggleMastered: {
                                    try? WordBookManager.shared.toggleMastered(entry)
                                }
                            )
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    // MARK: - Toolbar

    private var compactToolbar: some View {
        HStack(spacing: 8) {
            // 搜索框
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 13))
                TextField("搜索...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 140)

            // 筛选胶囊
            HStack(spacing: 3) {
                ForEach(WordFilter.allCases, id: \.self) { f in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            filter = f
                        }
                    } label: {
                        Text("\(f.rawValue) \(countForFilter(f))")
                            .font(.system(size: 12))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                filter == f
                                    ? AnyShapeStyle(Color.accentColor)
                                    : AnyShapeStyle(Color.clear),
                                in: Capsule()
                            )
                            .foregroundStyle(filter == f ? Color.white : Color.secondary)
                            .overlay(Capsule().strokeBorder(
                                filter == f ? Color.clear : Color.secondary.opacity(0.3),
                                lineWidth: 1
                            ))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // 排序切换
            Button {
                sortByAlpha.toggle()
            } label: {
                Image(systemName: sortByAlpha ? "textformat.abc" : "clock")
                    .font(.system(size: 13))
                    .foregroundStyle(sortByAlpha ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(sortByAlpha ? "当前：字母排序" : "当前：时间排序")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - CompactWordRow

private struct CompactWordRow: View {
    let entry: WordEntry
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onToggleMastered: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 主行
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.word)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(entry.isMastered ? .secondary : .primary)
                            .lineLimit(1)

                        if entry.isMastered {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                        }
                    }

                    if !entry.phonetic.isEmpty {
                        Text(entry.phonetic)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(entry.translation)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .trailing)

                Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            // 展开详情
            if isSelected {
                Divider().padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 6) {
                    // 完整翻译
                    Text(entry.translation)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    // 例句
                    if !entry.examples.isEmpty {
                        Divider()
                        Text("例句")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                        ForEach(entry.examples, id: \.self) { example in
                            Text(example)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Divider().padding(.horizontal, 12)

                // 操作栏
                HStack(spacing: 8) {
                    Text(Self.dateFormatter.string(from: entry.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)

                    if entry.pushCount > 0 {
                        Text("推送 \(entry.pushCount) 次")
                            .font(.system(size: 11))
                            .foregroundStyle(.quaternary)
                    }

                    Spacer()

                    Button {
                        onToggleMastered()
                    } label: {
                        Label(
                            entry.isMastered ? "取消掌握" : "已掌握",
                            systemImage: entry.isMastered ? "arrow.uturn.backward" : "checkmark.seal"
                        )
                        .font(.system(size: 13))
                        .foregroundStyle(entry.isMastered ? .orange : .green)
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(
            isSelected
                ? AnyShapeStyle(Color.accentColor.opacity(0.06))
                : AnyShapeStyle(Color.primary.opacity(0.04)),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.5) : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

