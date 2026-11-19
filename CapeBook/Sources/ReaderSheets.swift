import SwiftUI

struct TocView: View {
    let entries: [TocEntry]
    let currentChapter: Int
    let bookID: UUID
    let onSelect: (TocEntry) -> Void
    let onBookmark: (Bookmark) -> Void
    var currentPlace: (chapter: Int, range: NSRange) = (0, NSRange(location: 0, length: 0))
    var onToggleBookmark: () -> Void = {}
    var onSettings: () -> Void = {}
    var progress: Double = 0
    var liveSeconds: Int = 0                       // ещё не сохранённое время текущего чтения
    var placeLabel: (Double) -> String = { _ in "" }
    var onSeek: (Double) -> Void = { _ in }
    @EnvironmentObject var store: Store
    @State private var mode = 0
    @State private var scrub: Double = -1

    var body: some View {
        NavigationStack {
            Group {
                if mode == 0 { contents } else if mode == 1 { bookmarks } else { progressTab }
            }
            .listStyle(.insetGrouped)
            // одинаковый плотный фон во всех трёх вкладках — текст хорошо читается
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .environment(\.defaultMinListRowHeight, 48)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $mode) {
                        Text("Содержание").tag(0)
                        Text("Закладки").tag(1)
                        Text("Прогресс").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 290)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onSettings() } label: {
                        Text("Аа").font(.system(size: 17, weight: .semibold, design: .serif))
                    }
                    .tint(.green)
                    .accessibilityLabel("Оформление")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: вкладка «Прогресс»: шкала всей книги и время чтения
    private var progressTab: some View {
        let value = scrub >= 0 ? scrub : progress
        let mine = store.sessions.filter { $0.bookID == bookID }
        let total = mine.reduce(0) { $0 + $1.seconds } + liveSeconds
        let cal = Calendar.current
        let dayStart: Date = {
            let now = Date().addingTimeInterval(-5 * 3600)          // день начинается в 5:00
            return cal.startOfDay(for: now).addingTimeInterval(5 * 3600)
        }()
        let today = mine.filter { $0.start >= dayStart }.reduce(0) { $0 + $1.seconds } + liveSeconds
        let days = Set(mine.map { cal.startOfDay(for: $0.start.addingTimeInterval(-5 * 3600)) }).count
        let first = mine.map(\.start).min()
        let pagesRead = mine.reduce(0) { $0 + $1.pages }
        return List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int((value * 100).rounded())) %").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                        Spacer()
                        Text(placeLabel(value)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Slider(value: Binding(get: { value }, set: { scrub = $0 }), in: 0...1) { editing in
                        if !editing, scrub >= 0 { onSeek(scrub) }
                    }
                    .tint(.green)
                    Text("Перетащите ползунок, чтобы перейти в любое место книги.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            Section("Время чтения этой книги") {
                LabeledContent("Всего", value: Self.duration(total))
                LabeledContent("Сегодня", value: Self.duration(today))
                if days > 0 { LabeledContent("Дней с книгой", value: "\(days)") }
                if pagesRead > 0 { LabeledContent("Перевёрнуто страниц", value: "\(pagesRead)") }
                if let first { LabeledContent("Начато", value: first.formatted(.dateTime.day().month().year())) }
                if value > 0.02 && value < 1 && total > 120 {
                    let left = Double(total) / value * (1 - value)
                    LabeledContent("Осталось примерно", value: Self.duration(Int(left)))
                }
            }
        }
    }

    static func duration(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return "\(h) ч \(m) мин" }
        if m > 0 { return "\(m) мин" }
        return s > 0 ? "< 1 мин" : "0 мин"
    }

    private var bookmarks: some View {
        let list = store.book(bookID)?.bookmarks ?? []
        let marked = list.contains { $0.chapter == currentPlace.chapter && NSLocationInRange($0.offset, currentPlace.range) }
        return List {
            Section {
                Button { onToggleBookmark() } label: {
                    Label(marked ? "Убрать закладку с этой страницы" : "Добавить закладку",
                          systemImage: marked ? "bookmark.slash" : "bookmark.fill")
                        .foregroundStyle(marked ? Color.red : Color.green)
                }
            }
            Section {
            ForEach(list) { bm in
                Button { onBookmark(bm) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bm.snippet.isEmpty ? "Закладка" : bm.snippet).lineLimit(2).foregroundStyle(.green)
                        Text(bm.createdAt.formatted(.dateTime.day().month().hour().minute())).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))
                .swipeActions { Button(role: .destructive) { store.deleteBookmark(bookID: bookID, bm) } label: { Label("Удалить", systemImage: "trash") } }
            }
            }
        }
        .overlay {
            if list.isEmpty {
                ContentUnavailableView("Нет закладок", systemImage: "bookmark",
                                       description: Text("Нажмите «Добавить закладку» выше."))
                    .padding(.top, 80)
                    .allowsHitTesting(false)
            }
        }
    }

    private var contents: some View {
            ScrollViewReader { proxy in
                List { Section { ForEach(entries) { e in
                    Button { onSelect(e) } label: {
                        HStack {
                            Text(e.title)
                                .font(e.level <= 1 ? .body.weight(.semibold) : .body)
                                .foregroundStyle(.green)
                                .padding(.leading, CGFloat(max(0, e.level - 1)) * 16)
                            Spacer()
                            if e.chapter == currentChapter { Image(systemName: "bookmark.fill").foregroundStyle(.green) }
                        }
                    }
                    .id(e.id)
                    .listRowBackground(Color(.secondarySystemGroupedBackground))
                } } }
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
                    Stepper("Размер: \(Int(settings.fontSize))", value: $settings.fontSize, in: 11...40, step: 1)
                    Picker("Насыщенность", selection: $settings.fontWeight) {
                        Text("Обычный").tag(0)
                        Text("Плотнее").tag(1)
                        Text("Полужирный").tag(2)
                        Text("Жирный").tag(3)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Переносить слова", isOn: $settings.hyphenate)
                        Text("Слово, которое не помещается в строку, делится по слогам и переносится через дефис — пробелы между словами становятся ровнее.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Stepper("Межстрочный интервал: \(Int(settings.lineSpacing))", value: $settings.lineSpacing, in: -6...16, step: 1)
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
                    VStack(alignment: .leading) {
                        Text("Отступ текста снизу: \(Int(settings.bottomInset))")
                        Slider(value: $settings.bottomInset, in: -20...60, step: 2)
                    }
                    Toggle("Не поворачивать экран", isOn: $settings.lockOrientation)
                }
                Section {
                    Toggle("Поменять тап-зоны", isOn: $settings.swapTapZones)
                } footer: {
                    Text(settings.swapTapZones
                         ? "Тап по левому краю — следующая страница, по правому — предыдущая."
                         : "Тап по правому краю — следующая страница, по левому — предыдущая.")
                }
            }
            .navigationTitle("Оформление")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: settings) { _, new in onChange(new) }
        }
    }
}
