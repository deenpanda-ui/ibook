import SwiftUI

/// День в статистике начинается в 5:00 — чтение после полуночи относится к предыдущему дню
private func readingDay(_ d: Date) -> Date {
    Calendar.current.startOfDay(for: d.addingTimeInterval(-5 * 3600))
}
private func fmt(_ sec: Int) -> String {
    let m = (sec + 30) / 60
    if m < 60 { return "\(m) мин" }
    return m % 60 == 0 ? "\(m / 60) ч" : "\(m / 60) ч \(m % 60) мин"
}

struct StatsView: View {
    @EnvironmentObject var store: Store
    @State private var confirmReset = false
    @State private var openedBook: UUID?

    private var today: Date { readingDay(Date()) }
    private var todaySessions: [ReadingSession] { store.sessions.filter { readingDay($0.start) == today } }
    private var byDay: [Date: Int] {
        var m: [Date: Int] = [:]
        for s in store.sessions { m[readingDay(s.start), default: 0] += s.seconds }
        return m
    }
    private var streak: Int {
        var n = 0
        var d = today
        if (byDay[d] ?? 0) < 60, let y = Calendar.current.date(byAdding: .day, value: -1, to: d) { d = y }
        while (byDay[d] ?? 0) >= 60 {
            n += 1
            guard let p = Calendar.current.date(byAdding: .day, value: -1, to: d) else { break }
            d = p
        }
        return n
    }
    /// Среднее время в день — по дням, когда вы читали
    private var averagePerDay: Int {
        let days = byDay.values.filter { $0 > 0 }.count
        guard days > 0 else { return 0 }
        return byDay.values.reduce(0, +) / days
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    todayCard
                    HStack(spacing: 12) {
                        tile(fmt(store.sessions.reduce(0) { $0 + $1.seconds }), "всего за чтением")
                        tile("\(streak)", "дней подряд")
                    }
                    HStack(spacing: 12) {
                        tile("\(store.books.filter { $0.isRead }.count)", "книг прочитано")
                        tile(fmt(averagePerDay), "в среднем в день")
                    }
                    finished
                    Button(role: .destructive) { confirmReset = true } label: {
                        Text("Сбросить статистику").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .padding(.top, 10)
                    ShareLink(item: Diagnostics.reportFile()) {
                        Label("Отправить диагностику разработчику", systemImage: "ladybug").font(.footnote)
                    }
                    .padding(.top, 4)
                    Text("Время идёт, только пока открыт текст книги. Если 20 секунд нет касаний, перелистываний и движения телефона — таймер на паузе. День заканчивается в 5:00.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
            .navigationTitle("Моё чтение")
            .confirmationDialog("Сбросить статистику?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Сбросить", role: .destructive) { store.resetStats() }
            } message: { Text("Будут удалены время чтения и история по дням. Книги и цитаты останутся.") }
        }
    }

    private var todayCard: some View {
        let total = todaySessions.reduce(0) { $0 + $1.seconds }
        var perBook: [UUID: (sec: Int, from: Double?, to: Double?)] = [:]
        for s in todaySessions {
            var e = perBook[s.bookID] ?? (0, nil, nil)
            e.sec += s.seconds
            if let f = s.progressFrom { e.from = min(e.from ?? f, f) }
            if let t = s.progressTo { e.to = max(e.to ?? t, t) }
            perBook[s.bookID] = e
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("СЕГОДНЯ").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.green)
            Text(fmt(total)).font(.custom("Literata-Bold", size: 38))
            if perBook.isEmpty {
                Text("Сегодня вы ещё не открывали книги").foregroundStyle(.secondary)
            }
            ForEach(Array(perBook.keys), id: \.self) { id in
                let e = perBook[id]!
                let book = store.book(id)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book?.title ?? "Книга").font(.headline).lineLimit(1)
                        if let a = book?.author, !a.isEmpty { Text(a).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(fmt(e.sec)).font(.subheadline.weight(.semibold))
                        if let f = e.from, let t = e.to {
                            Text("+\(max(0, Int(((t - f) * 100).rounded())))% · \(Int((t * 100).rounded()))%")
                                .font(.caption.weight(.semibold)).foregroundStyle(.green)
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassEffect(.regular.tint(.green.opacity(0.15)), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Как читалась книга: период, дни чтения, общее время
    private func bookDetails(_ b: Book) -> some View {
        let mine = store.sessions.filter { $0.bookID == b.id }
        let total = mine.reduce(0) { $0 + $1.seconds }
        let days = Set(mine.map { readingDay($0.start) }).count
        let first = mine.map(\.start).min()
        let last = b.readAt ?? mine.map(\.start).max()
        let dateFmt = Date.FormatStyle.dateTime.day().month().year()
        return VStack(alignment: .leading, spacing: 6) {
            if mine.isEmpty {
                Text("Нет записей о чтении этой книги — возможно, она была прочитана до установки или статистику сбрасывали.")
                    .foregroundStyle(.secondary)
            } else {
                if let first, let last {
                    let span = (Calendar.current.dateComponents([.day], from: readingDay(first), to: readingDay(last)).day ?? 0) + 1
                    row("Период", "\(first.formatted(dateFmt)) — \(last.formatted(dateFmt))")
                    row("Заняло", "\(span) \(dayWord(span))")
                }
                row("Дней чтения", "\(days)")
                row("Время за чтением", fmt(total))
                if days > 0 { row("В среднем в день", fmt(total / days)) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing)
        }
    }
    private func dayWord(_ n: Int) -> String {
        let a = n % 100, b = n % 10
        if a >= 11 && a <= 14 { return "дней" }
        if b == 1 { return "день" }
        if b >= 2 && b <= 4 { return "дня" }
        return "дней"
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.bold))
            Text(label).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var finished: some View {
        let done = store.books.filter { $0.isRead }.sorted { ($0.readAt ?? .distantPast) > ($1.readAt ?? .distantPast) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Прочитанные книги").font(.headline)
            if done.isEmpty {
                Text("Отметьте книгу прочитанной в меню книги в библиотеке.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(done) { b in
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(.snappy) { openedBook = openedBook == b.id ? nil : b.id }
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.title).lineLimit(1).foregroundStyle(.primary)
                                // сразу видно: сколько времени и сколько дней читали
                                let mine = store.sessions.filter { $0.bookID == b.id }
                                if !mine.isEmpty {
                                    let days = Set(mine.map { readingDay($0.start) }).count
                                    Text("\(fmt(mine.reduce(0) { $0 + $1.seconds })) · \(days) \(dayWord(days)) чтения")
                                        .font(.caption).foregroundStyle(.green)
                                }
                            }
                            Spacer()
                            if let d = b.readAt { Text(d.formatted(.dateTime.day().month())).foregroundStyle(.secondary) }
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .rotationEffect(.degrees(openedBook == b.id ? 180 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if openedBook == b.id { bookDetails(b) }
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
