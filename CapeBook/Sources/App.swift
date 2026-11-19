import SwiftUI
import UniformTypeIdentifiers

@main
struct CapeBookApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .onOpenURL { url in store.importBook(from: url) }   // «Открыть в CapeBook» из «Файлов» и мессенджеров
                .onAppear { store.addDefaultBookIfNeeded() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        TabView(selection: $store.tab) {
            Tab("Библиотека", systemImage: "house.fill", value: 0) { LibraryView() }
            Tab("Цитаты", systemImage: "quote.opening", value: 1) { QuotesView() }
            Tab("Статистика", systemImage: "books.vertical.fill", value: 2) { StatsView() }
        }
        .tint(Color(red: 0.43, green: 0.82, blue: 0.53))   // зелёный акцент (белый делал кнопки «невидимыми»)
    }
}

// MARK: - Обложка-заглушка для книг без картинки

struct PlaceholderCover: View {
    let title: String
    let author: String

    private static let palette: [(Color, Color)] = [
        (Color(red: 0.55, green: 0.20, blue: 0.20), Color(red: 0.33, green: 0.10, blue: 0.10)),
        (Color(red: 0.55, green: 0.36, blue: 0.16), Color(red: 0.33, green: 0.20, blue: 0.08)),
        (Color(red: 0.22, green: 0.36, blue: 0.50), Color(red: 0.11, green: 0.20, blue: 0.30)),
        (Color(red: 0.24, green: 0.40, blue: 0.30), Color(red: 0.12, green: 0.22, blue: 0.16)),
        (Color(red: 0.38, green: 0.30, blue: 0.52), Color(red: 0.20, green: 0.15, blue: 0.30)),
        (Color(red: 0.50, green: 0.43, blue: 0.22), Color(red: 0.30, green: 0.25, blue: 0.10))
    ]
    private var colors: (Color, Color) {
        var h = 0
        for u in (title + author).unicodeScalars { h = (h &* 31 &+ Int(u.value)) & 0x7fff_ffff }
        return Self.palette[h % Self.palette.count]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)
            RoundedRectangle(cornerRadius: 2).strokeBorder(.white.opacity(0.35), lineWidth: 0.8).padding(8)
            VStack(spacing: 8) {
                Text(author).font(.custom("Avenir Next", size: 13)).foregroundStyle(.white.opacity(0.65))
                Text(title).font(.custom("Avenir Next", size: 17).weight(.semibold)).foregroundStyle(.white)
            }
            .multilineTextAlignment(.center)
            .lineLimit(5)
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 34)
        }
    }
}

struct CoverView: View {
    let book: Book
    @EnvironmentObject var store: Store

    var body: some View {
        // рамка строго 2:3 — обложка заполняет её целиком, лишнее обрезается; так все книги одного размера
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if let url = store.coverURL(book), let img = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    PlaceholderCover(title: book.title, author: book.author)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(alignment: .center) {
                if book.isRead { ReadStamp().offset(y: 40) }
            }
            .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
    }
}

struct ReadStamp: View {
    var body: some View {
        Text("ПРОЧИТАНО")
            .font(.system(size: 13, weight: .heavy))
            .tracking(2)
            .foregroundStyle(Color(red: 0.25, green: 0.75, blue: 0.39))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color(red: 0.04, green: 0.12, blue: 0.06).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(red: 0.25, green: 0.75, blue: 0.39), lineWidth: 2))
            .rotationEffect(.degrees(-14))
    }
}
