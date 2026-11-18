import SwiftUI
import Charts

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
    private var last14: [(Date, Int)] {
        (0..<14).reversed().compactMap { i in
            Calendar.current.date(byAdding: .day, value: -i, to: today).map { ($0, byDay[$0] ?? 0) }
        }
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
                        tile("\(store.sessions.reduce(0) { $0 + $1.pages })", "страниц")
                    }
                    chart
                    finished
                    Button(role: .destructive) { confirmReset = true } label: {
                        Text("Сбросить статистику").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .padding(.top, 10)
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

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.bold))
            Text(label).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Последние 14 дней").font(.headline)
            Chart(last14, id: \.0) { item in
                BarMark(x: .value("День", item.0, unit: .day), y: .value("Минуты", Double(item.1) / 60))
                    .foregroundStyle(.green.gradient)
                    .cornerRadius(4)
            }
            .frame(height: 160)
        }
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
                HStack {
                    Text(b.title).lineLimit(1)
                    Spacer()
                    if let d = b.readAt { Text(d.formatted(.dateTime.day().month())).foregroundStyle(.secondary) }
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
