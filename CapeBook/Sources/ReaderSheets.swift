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
                    Picker("Шрифт", selection: $settings.fontFamily) {
                        ForEach(ReaderFonts.all.indices, id: \.self) { i in
                            let f = ReaderFonts.all[i]
                            Text(f.title).font(.custom(f.family == "Literata" ? "Literata-Regular" : f.family, size: 17)).tag(f.family)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Stepper("Размер: \(Int(settings.fontSize))", value: $settings.fontSize, in: 14...34, step: 1)
                    Stepper("Межстрочный: \(Int(settings.lineSpacing))", value: $settings.lineSpacing, in: 0...14, step: 1)
                }
                Section("Страница") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Фон")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(PaperTheme.allCases, id: \.self) { t in
                                    Button { settings.theme = t } label: {
                                        VStack(spacing: 6) {
                                            ZStack {
                                                if let img = t.image { Image(uiImage: img).resizable().scaledToFill() }
                                                else { Color(t.background) }
                                                Text("Аа").font(.custom("Literata-Regular", size: 20)).foregroundStyle(Color(t.text))
                                            }
                                            .frame(width: 64, height: 90)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(settings.theme == t ? Color.green : Color.white.opacity(0.15), lineWidth: settings.theme == t ? 3 : 1))
                                            Text(t.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        .frame(width: 84)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
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
