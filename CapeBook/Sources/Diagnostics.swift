import Foundation
import UIKit

/// Журнал событий и вылетов. Отправляется из «Статистики» кнопкой «Отправить диагностику».
enum Diagnostics {
    static var logURL: URL { Paths.support.appendingPathComponent("diagnostics.txt") }
    private static let lock = NSLock()

    static func log(_ message: String) {
        let f = DateFormatter()
        f.dateFormat = "dd.MM HH:mm:ss"
        let line = "\(f.string(from: Date())) \(message)\n"
        lock.lock(); defer { lock.unlock() }
        let url = logURL
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
        // журнал не больше ~300 КБ: оставляем последнюю половину
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int, size > 300_000,
           let data = try? Data(contentsOf: url) {
            try? data.suffix(150_000).write(to: url)
        }
    }

    static func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { e in
            let stack = e.callStackSymbols.prefix(30).joined(separator: "\n")
            Diagnostics.log("=== ВЫЛЕТ: \(e.name.rawValue): \(e.reason ?? "")\n\(stack)")
        }
        for sig in [SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP] {
            signal(sig) { s in
                let stack = Thread.callStackSymbols.prefix(30).joined(separator: "\n")
                Diagnostics.log("=== СБОЙ: сигнал \(s)\n\(stack)")
                signal(s, SIG_DFL)
                raise(s)
            }
        }
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        log("запуск CapeBook \(v) (\(b)), iOS \(UIDevice.current.systemVersion)")
    }

    /// Файл отчёта для отправки
    static func reportFile() -> URL {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        var text = "CapeBook \(v) (сборка \(b)) · iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model)\n"
        text += "Книг: \(Store.shared.books.count), цитат: \(Store.shared.quotes.count), записей чтения: \(Store.shared.sessions.count)\n\n"
        text += (try? String(contentsOf: logURL, encoding: .utf8)) ?? "(журнал пуст)"
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("CapeBook-отчёт.txt")
        try? text.write(to: out, atomically: true, encoding: .utf8)
        return out
    }
}
