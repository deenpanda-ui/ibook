import SwiftUI

struct QuotesView: View {
    @EnvironmentObject var store: Store
    @State private var query = ""

    private var bookFilter: UUID? { store.quotesFilter }

    private var filtered: [Quote] {
        store.quotes.filter { q in
            (bookFilter == nil || q.bookID == bookFilter) &&
            (query.isEmpty || q.text.localizedCaseInsensitiveContains(query) || q.bookTitle.localizedCaseInsensitiveContains(query))
        }
    }
    private var booksWithQuotes: [(UUID, String, Int)] {
        var seen: [UUID: (String, Int)] = [:]
        var order: [UUID] = []
        for q in store.quotes {
            if seen[q.bookID] == nil { order.append(q.bookID); seen[q.bookID] = (q.bookTitle, 0) }
            seen[q.bookID]!.1 += 1
        }
        return order.map { ($0, seen[$0]!.0, seen[$0]!.1) }
    }

    var body: some View {
        NavigationStack {
            List {
                if booksWithQuotes.count > 1 || bookFilter != nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("Все", count: store.quotes.count, active: bookFilter == nil) { store.quotesFilter = nil }
                            ForEach(booksWithQuotes, id: \.0) { item in
                                chip(item.1, count: item.2, active: bookFilter == item.0) { store.quotesFilter = item.0 }
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                ForEach(filtered) { q in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(q.text).font(.custom("Times New Roman", size: 18))
                        Text([q.bookAuthor, q.bookTitle].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .contextMenu {
                        Button { UIPasteboard.general.string = q.signed } label: { Label("Скопировать", systemImage: "doc.on.doc") }
                        ShareLink(item: q.signed) { Label("Поделиться", systemImage: "square.and.arrow.up") }
                        Button(role: .destructive) { withAnimation { store.deleteQuote(q) } } label: { Label("Удалить", systemImage: "trash") }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { withAnimation { store.deleteQuote(q) } } label: {
                            Label("Удалить", systemImage: "trash").labelStyle(.iconOnly)
                        }
                        .tint(.red)
                        ShareLink(item: q.signed) { Label("Поделиться", systemImage: "square.and.arrow.up").labelStyle(.iconOnly) }
                            .tint(.green)
                    }
                }
            }
            .overlay {
                if bookFilter != nil && filtered.isEmpty && !store.quotes.isEmpty {
                    ContentUnavailableView("В этой книге пока нет цитат", systemImage: "quote.opening",
                                           description: Text("Выделите текст в книге и нажмите «В цитаты»."))
                }
                if store.quotes.isEmpty {
                    ContentUnavailableView("Пока нет цитат", systemImage: "quote.opening",
                                           description: Text("Выделите текст в книге и нажмите «В цитаты»."))
                }
            }
            .searchable(text: $query, prompt: "Поиск по цитатам")
            .navigationTitle("Цитаты")
        }
    }

    private func chip(_ title: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).lineLimit(1)
                Text("\(count)").foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(active ? Color.green.opacity(0.35) : Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
