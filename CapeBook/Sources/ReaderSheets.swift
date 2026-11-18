import SwiftUI

struct TocView: View {
    let entries: [TocEntry]
    let currentChapter: Int
    let bookID: UUID
    let onSelect: (TocEntry) -> Void
    let onBookmark: (Bookmark) -> Void
    @EnvironmentObject var store: Store
    @State private var mode = 0

    var body: some View {
        NavigationStack {
            Group {
                if mode == 0 { contents } else { bookmarks }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $mode) {
                        Text("Содержание").tag(0)
                        Text("Закладки").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var bookmarks: some View {
        let list = store.book(bookID)?.bookmarks ?? []
        return List {
            ForEach(list) { bm in
                Button { onBookmark(bm) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bm.snippet.isEmpty ? "Закладка" : bm.snippet).lineLimit(2)
                        Text(bm.createdAt.formatted(.dateTime.day().month().hour().minute())).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions { Button(role: .destructive) { store.deleteBookmark(bookID: bookID, bm) } label: { Label("Удалить", systemImage: "trash") } }
            }
        }
        .overlay {
            if list.isEmpty {
                ContentUnavailableView("Нет закладок", systemImage: "bookmark",
                                       description: Text("Нажмите на значок закладки вверху страницы."))
            }
        }
    }

    private var contents: some View {
            ScrollViewReader { proxy in
                List(entries) { e in
                    Button { onSelect(e) } label: {
                        HStack {
                            Text(e.title)
                                .font(e.level <= 1 ? .body.weight(.semibold) : .body)
                                .padding(.leading, CGFloat(max(0, e.level - 1)) * 16)
                            Spacer()
                            if e.chapter == currentChapter { Image(systemName: "bookmark.fill").foregroundStyle(.green) }
                        }
                    }
                    .id(e.id)
                }
                .onAppear {
                    if let e = entries.last(where: { $0.chapter <= currentChapter }) { proxy.scrollTo(e.id, anchor: .center) }
                }
            }
    }
}

struct ReaderSettingsView: View {
    @State var settings: ReaderSettings
    let onChange: (ReaderSettings) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Шрифт") {
                    Stepper("Размер: \(Int(settings.fontSize))", value: $settings.fontSize, in: 14...34, step: 1)
                    Stepper("Межстрочный: \(Int(settings.lineSpacing))", value: $settings.lineSpacing, in: 0...14, step: 1)
                }
                Section("Страница") {
                    Picker("Фон", selection: $settings.theme) {
                        ForEach(PaperTheme.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    VStack(alignment: .leading) {
                        Text("Отступ текста сверху: \(Int(settings.topInset))")
                        Slider(value: $settings.topInset, in: 0...80, step: 2)
                    }
                    Toggle("Не поворачивать экран", isOn: $settings.lockOrientation)
                }
            }
            .navigationTitle("Оформление")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: settings) { _, new in onChange(new) }
        }
    }
}
