import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var store: Store
    @State private var importing = false
    @State private var reading: Book?
    @State private var toDelete: Book?

    private let columns = [GridItem(.flexible(), spacing: 26), GridItem(.flexible(), spacing: 26)]
    private var types: [UTType] {
        var t: [UTType] = [.epub]
        if let fb2 = UTType(filenameExtension: "fb2") { t.append(fb2) }
        return t
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.books.isEmpty {
                    ContentUnavailableView("Здесь появятся ваши книги",
                                           systemImage: "books.vertical",
                                           description: Text("Нажмите «+» и выберите EPUB или FB2 в «Файлах»."))
                        .padding(.top, 80)
                }
                LazyVGrid(columns: columns, spacing: 30) {
                    ForEach(store.books) { book in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { open(book) } label: { CoverView(book: book) }
                                .buttonStyle(.plain)
                            HStack {
                                Text(book.isRead ? "" : (book.progress > 0 ? "\(max(1, Int((book.progress * 100).rounded()))) %" : "НОВАЯ"))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                menu(book)
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .navigationTitle("Библиотека")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: { Image(systemName: "plus") }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: types, allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { for u in urls { store.importBook(from: u) } }
            }
            .fullScreenCover(item: $reading) { book in
                ReaderScreen(book: book).ignoresSafeArea()
            }
            .confirmationDialog("Удалить книгу?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                                titleVisibility: .visible, presenting: toDelete) { book in
                Button("Удалить «\(book.title)»", role: .destructive) { store.delete(book) }
            } message: { _ in Text("Книга, её закладки и место чтения будут удалены. Цитаты останутся.") }
        }
    }

    private func open(_ book: Book) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reading = book
    }

    private func menu(_ book: Book) -> some View {
        Menu {
            Button { open(book) } label: { Label("Читать", systemImage: "book") }
            ShareLink(item: store.fileURL(book)) { Label("Поделиться книгой", systemImage: "square.and.arrow.up") }
            Button {
                var b = book
                b.isRead.toggle()
                b.readAt = b.isRead ? Date() : nil
                store.update(b)
            } label: {
                Label(book.isRead ? "Снять отметку «Прочитано»" : "Отметить прочитанной",
                      systemImage: book.isRead ? "xmark.circle" : "checkmark.circle")
            }
            Button(role: .destructive) { toDelete = book } label: { Label("Удалить из библиотеки", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 32, height: 24)
        }
    }
}
