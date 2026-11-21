import Foundation
import SwiftUI

// MARK: - Книга в библиотеке

enum BookFormat: String, Codable {
    case epub, fb2
}

struct Book: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var author: String
    var fileName: String              // файл в Documents/Books
    var format: BookFormat
    var coverFileName: String?        // файл в Application Support/Covers
    var addedAt: Date = Date()
    var lastOpenedAt: Date?
    var progress: Double = 0          // 0...1
    var chapter: Int = 0              // место чтения: глава
    var offset: Int = 0               //               и символ внутри главы
    var isRead: Bool = false
    var readAt: Date?
    var bookmarks: [Bookmark]?        // необязательное поле — старые записи читаются без него
}

struct Bookmark: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var chapter: Int
    var offset: Int
    var snippet: String
    var createdAt: Date = Date()
}

// MARK: - Цитата

struct Quote: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var bookID: UUID
    var bookTitle: String
    var bookAuthor: String
    var text: String
    var createdAt: Date = Date()

    /// «текст» — Автор, «Книга»
    var signed: String {
        var s = "«" + text.trimmingCharacters(in: .whitespacesAndNewlines) + "»"
        let parts = [bookAuthor, bookTitle.isEmpty ? "" : "«\(bookTitle)»"].filter { !$0.isEmpty }
        if !parts.isEmpty { s += "\n\n— " + parts.joined(separator: ", ") }
        return s
    }
}

// MARK: - Отрезок чтения (для статистики)

struct ReadingSession: Codable {
    var bookID: UUID
    var start: Date
    var seconds: Int
    var pages: Int
    var progressFrom: Double?
    var progressTo: Double?
}

// MARK: - Пути

enum Paths {
    static let fm = FileManager.default
    static var documents: URL { fm.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var support: URL {
        let u = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var books: URL {
        let u = documents.appendingPathComponent("Books", isDirectory: true)
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var covers: URL {
        let u = support.appendingPathComponent("Covers", isDirectory: true)
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

// MARK: - Хранилище (JSON-файлы)

final class Store: ObservableObject {
    static let shared = Store()

    @Published var books: [Book] = []
    @Published var quotes: [Quote] = []
    @Published var sessions: [ReadingSession] = []
    // навигация: открытая вкладка и фильтр цитат (для «Цитаты из книги»)
    @Published var tab = 0
    @Published var quotesFilter: UUID?

    private let booksURL = Paths.support.appendingPathComponent("books.json")
    private let quotesURL = Paths.support.appendingPathComponent("quotes.json")
    private let sessionsURL = Paths.support.appendingPathComponent("sessions.json")

    init() {
        books = Self.load(booksURL) ?? []
        quotes = Self.load(quotesURL) ?? []
        sessions = Self.load(sessionsURL) ?? []
    }

    private static func load<T: Decodable>(_ url: URL) -> T? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(T.self, from: d)
    }
    private func save<T: Encodable>(_ value: T, to url: URL) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        if let d = try? enc.encode(value) { try? d.write(to: url, options: .atomic) }
    }
    func saveBooks() { save(books, to: booksURL) }
    func saveQuotes() { save(quotes, to: quotesURL) }
    func saveSessions() { save(sessions, to: sessionsURL) }

    // книги
    func book(_ id: UUID) -> Book? { books.first { $0.id == id } }
    func update(_ book: Book) {
        if let i = books.firstIndex(where: { $0.id == book.id }) { books[i] = book; saveBooks() }
    }
    func fileURL(_ book: Book) -> URL { Paths.books.appendingPathComponent(book.fileName) }
    func coverURL(_ book: Book) -> URL? { book.coverFileName.map { Paths.covers.appendingPathComponent($0) } }

    func delete(_ book: Book) {
        try? Paths.fm.removeItem(at: fileURL(book))
        if let c = coverURL(book) { try? Paths.fm.removeItem(at: c) }
        books.removeAll { $0.id == book.id }
        saveBooks()
    }

    /// Добавить книгу из файла (из «Файлов», «Поделиться» или из приложения)
    @discardableResult
    func importBook(from url: URL) -> Book? {
        let ext = url.pathExtension.lowercased()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if ext == "zip" { return importZip(url) }
        guard let format = BookFormat(rawValue: ext) else {
            Diagnostics.log("импорт: неизвестный формат \(url.lastPathComponent)")
            return nil
        }
        Diagnostics.log("импорт: \(url.lastPathComponent)")
        // та же книга уже есть — не дублировать
        if let existing = books.first(where: { $0.fileName == url.lastPathComponent }) { return existing }
        var name = url.lastPathComponent
        var dest = Paths.books.appendingPathComponent(name)
        var n = 1
        while Paths.fm.fileExists(atPath: dest.path) {
            name = url.deletingPathExtension().lastPathComponent + "-\(n)." + ext
            dest = Paths.books.appendingPathComponent(name); n += 1
        }
        do { try Paths.fm.copyItem(at: url, to: dest) } catch { return nil }
        let meta = BookParser.metadata(url: dest, format: format)
        var book = Book(title: meta.title.isEmpty ? url.deletingPathExtension().lastPathComponent : meta.title,
                        author: meta.author, fileName: name, format: format)
        if let cover = meta.cover {
            let cname = book.id.uuidString + ".img"
            try? cover.write(to: Paths.covers.appendingPathComponent(cname))
            book.coverFileName = cname
        }
        books.insert(book, at: 0)
        saveBooks()
        return book
    }

    /// Книга в ZIP (часто «книга.fb2.zip»): достаём первую книгу из архива
    private func importZip(_ url: URL) -> Book? {
        guard let zip = ZipArchive(url: url) else { Diagnostics.log("импорт: не удалось открыть архив"); return nil }
        let names = zip.entries.keys.sorted()
        guard let name = names.first(where: { $0.lowercased().hasSuffix(".fb2") }) ?? names.first(where: { $0.lowercased().hasSuffix(".epub") }),
              let data = zip.read(name) else { Diagnostics.log("импорт: в архиве нет FB2/EPUB"); return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent((name as NSString).lastPathComponent)
        try? data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return importBook(from: tmp)
    }

    /// При первом запуске — книга по умолчанию (Чехов, «Размазня»)
    func addDefaultBookIfNeeded() {
        let key = "CapeBookDefaultBookAdded"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if let u = Bundle.main.url(forResource: "chehov_razmaznya", withExtension: "epub") { importBook(from: u) }
    }

    // цитаты
    func addQuote(_ text: String, book: Book) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        quotes.insert(Quote(bookID: book.id, bookTitle: book.title, bookAuthor: book.author, text: t), at: 0)
        saveQuotes()
    }
    func deleteQuote(_ q: Quote) { quotes.removeAll { $0.id == q.id }; saveQuotes() }

    // закладки
    func toggleBookmark(bookID: UUID, chapter: Int, range: NSRange, snippet: String) -> Bool {
        guard var b = book(bookID) else { return false }
        var list = b.bookmarks ?? []
        if let i = list.firstIndex(where: { $0.chapter == chapter && NSLocationInRange($0.offset, range) }) {
            list.remove(at: i)
            b.bookmarks = list; update(b)
            return false
        }
        list.append(Bookmark(chapter: chapter, offset: range.location, snippet: snippet))
        list.sort { ($0.chapter, $0.offset) < ($1.chapter, $1.offset) }
        b.bookmarks = list; update(b)
        return true
    }
    func deleteBookmark(bookID: UUID, _ bm: Bookmark) {
        guard var b = book(bookID) else { return }
        b.bookmarks?.removeAll { $0.id == bm.id }
        update(b)
    }

    // статистика
    func addSession(_ s: ReadingSession) {
        guard s.seconds >= 5 else { return }
        sessions.append(s); saveSessions()
    }
    func resetStats() { sessions = []; saveSessions() }
}


// MARK: - Скорость чтения: считается по вашим отрезкам чтения

enum ReadingSpeed {
    /// средняя скорость взрослого читателя — пока ваших данных мало
    static let defaultCPM = 1000.0

    /// Объём книги в знаках (считается один раз при открытии книги)
    static func chars(_ id: UUID) -> Int? {
        let v = UserDefaults.standard.integer(forKey: "chars." + id.uuidString)
        return v > 0 ? v : nil
    }
    static func setChars(_ id: UUID, _ n: Int) { UserDefaults.standard.set(n, forKey: "chars." + id.uuidString) }

    /// Замер по отрезкам: знаков в минуту и сколько минут чтения учтено.
    /// Отрезки короче 30 с и с нереальной скоростью (перемотка, прыжки ползунком) не считаются.
    static func measure(_ sessions: [ReadingSession], book: UUID? = nil) -> (cpm: Double, minutes: Double, count: Int) {
        var sum = 0.0, secs = 0.0, n = 0
        for s in sessions where book == nil || s.bookID == book {
            guard s.seconds >= 30, let f = s.progressFrom, let t = s.progressTo, t > f,
                  let total = Self.chars(s.bookID) else { continue }
            let c = (t - f) * Double(total)
            let cpm = c / (Double(s.seconds) / 60)
            guard cpm >= 150, cpm <= 5000 else { continue }
            sum += c; secs += Double(s.seconds); n += 1
        }
        return secs > 0 ? (sum / (secs / 60), secs / 60, n) : (0, 0, 0)
    }

    /// Ваша скорость для этой книги: общая (плавно уходит от средней по мере накопления данных),
    /// а если эту книгу читали больше 10 минут — с учётом темпа именно в ней
    static func estimate(book: UUID, sessions: [ReadingSession]) -> (cpm: Double, measuredMinutes: Double) {
        let all = measure(sessions)
        var cpm = (all.cpm * all.minutes + defaultCPM * 10) / (all.minutes + 10)
        let mine = measure(sessions, book: book)
        if mine.minutes >= 10 { cpm = (cpm + mine.cpm * 2) / 3 }
        return (cpm, all.minutes)
    }
}
