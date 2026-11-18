import SwiftUI

struct TocView: View {
    let entries: [TocEntry]
    let currentChapter: Int
    let onSelect: (TocEntry) -> Void

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Содержание")
            .navigationBarTitleDisplayMode(.inline)
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
                }
            }
            .navigationTitle("Оформление")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: settings) { _, new in onChange(new) }
        }
    }
}
