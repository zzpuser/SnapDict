import SwiftUI
import SwiftData

// MARK: - Filter

enum WordFilter: String, CaseIterable {
    case all = "全部"
    case learning = "学习中"
    case mastered = "已掌握"
}

// MARK: - Main View

struct WordBookView: View {
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

        // Filter by status
        switch filter {
        case .learning: result = result.filter { !$0.isMastered }
        case .mastered: result = result.filter(\.isMastered)
        case .all: break
        }

        // Filter by search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.word.lowercased().contains(query) ||
                $0.translation.lowercased().contains(query)
            }
        }

        // Sort
        if sortByAlpha {
            result = result.sorted { $0.word.lowercased() < $1.word.lowercased() }
        }

        return result
    }

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)
    ]

    private func countForFilter(_ f: WordFilter) -> Int {
        switch f {
        case .all: return stats.total
        case .learning: return stats.learning
        case .mastered: return stats.mastered
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar: search + filter + sort
            toolbar

            Divider()

            // Content
            if filteredWords.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredWords) { entry in
                            WordCard(
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
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 580, minHeight: 480)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            // Search
            HStack(spacing: 6) {
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
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            .frame(maxWidth: 180)

            Spacer()

            // Filter pills
            HStack(spacing: 4) {
                ForEach(WordFilter.allCases, id: \.self) { f in
                    filterPill(f)
                }
            }

            Divider().frame(height: 18)

            // Sort toggle
            Button {
                sortByAlpha.toggle()
            } label: {
                Label(sortByAlpha ? "A→Z" : "最新", systemImage: sortByAlpha ? "textformat.abc" : "clock")
                    .font(.caption)
                    .foregroundStyle(sortByAlpha ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(sortByAlpha ? "当前：字母排序，点击切换为时间排序" : "当前：时间排序，点击切换为字母排序")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func filterPill(_ f: WordFilter) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                filter = f
            }
        } label: {
            Text("\(f.rawValue) \(countForFilter(f))")
                .font(.caption)
                .padding(.horizontal, 10)
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

    // MARK: Empty State

    private var emptyState: some View {
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
    }
}

// MARK: - Word Card

private struct WordCard: View {
    let entry: WordEntry
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onToggleMastered: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(entry.word)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(entry.isMastered ? .secondary : .primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if entry.isMastered {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.green)
                    }
                }

                if !entry.phonetic.isEmpty {
                    Text(entry.phonetic)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Text(entry.translation)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(isSelected ? nil : 2)
                    .fixedSize(horizontal: false, vertical: isSelected)
            }
            .padding(12)

            // Expanded detail: examples
            if isSelected && !entry.examples.isEmpty {
                Divider()
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 6) {
                    Text("例句")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)

                    ForEach(entry.examples, id: \.self) { example in
                        Text(example)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
            }

            // Footer
            if isSelected {
                Divider()
                cardFooter
            } else {
                HStack {
                    Text(Self.dateFormatter.string(from: entry.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.07),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .shadow(color: .black.opacity(isSelected ? 0.12 : 0.05), radius: isSelected ? 8 : 3, y: isSelected ? 3 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var cardBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.06))
        } else {
            return AnyShapeStyle(.background.opacity(0.8))
        }
    }

    private var cardFooter: some View {
        HStack(spacing: 8) {
            Text(Self.dateFormatter.string(from: entry.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let pushed = entry.lastPushedAt {
                Text("·")
                    .foregroundStyle(.quaternary)
                    .font(.caption2)
                Text("推送 \(entry.pushCount) 次")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .help("上次推送：\(pushed.formatted())")
            }

            Spacer()

            Button {
                onToggleMastered()
            } label: {
                Label(
                    entry.isMastered ? "取消掌握" : "已掌握",
                    systemImage: entry.isMastered ? "arrow.uturn.backward" : "checkmark.seal"
                )
                .font(.caption)
                .foregroundStyle(entry.isMastered ? .orange : .green)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: WordEntry.self, configurations: config)
    let ctx = container.mainContext

    let samples: [(String, String, String, [String], Bool)] = [
        ("ephemeral", "/ɪˈfem.ər.əl/", "adj. 短暂的；朝生暮死的", ["The ephemeral nature of fame.", "Ephemeral pleasures fade quickly."], false),
        ("serendipity", "/ˌser.ənˈdɪp.ɪ.ti/", "n. 意外发现美好事物的能力；机缘巧合", ["It was pure serendipity that we met."], true),
        ("ubiquitous", "/juːˈbɪk.wɪ.təs/", "adj. 无处不在的；普遍存在的", ["Smartphones have become ubiquitous."], false),
        ("melancholy", "/ˈmel.ən.kɒl.i/", "n./adj. 忧郁；悲愁", [], true),
        ("resilience", "/rɪˈzɪl.i.əns/", "n. 韧性；恢复力", ["She showed great resilience after the loss."], false),
        ("nostalgia", "/nɒˈstæl.dʒə/", "n. 怀旧；思乡情", ["A wave of nostalgia washed over him."], false),
    ]

    for (i, s) in samples.enumerated() {
        let e = WordEntry(
            word: s.0, phonetic: s.1, translation: s.2, examples: s.3,
            createdAt: Date().addingTimeInterval(Double(-i) * 86400),
            pushCount: i, isMastered: s.4
        )
        ctx.insert(e)
    }

    return WordBookView()
        .modelContainer(container)
        .frame(width: 680, height: 560)
}

