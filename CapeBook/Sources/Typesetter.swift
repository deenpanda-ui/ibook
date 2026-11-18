import UIKit

// MARK: - Настройки чтения

enum PaperTheme: Int, CaseIterable {
    case paper, sepia, gray, night

    var background: UIColor {
        switch self {
        case .paper: return UIColor(red: 0.97, green: 0.95, blue: 0.90, alpha: 1)
        case .sepia: return UIColor(red: 0.93, green: 0.87, blue: 0.75, alpha: 1)
        case .gray: return UIColor(red: 0.42, green: 0.43, blue: 0.37, alpha: 1)
        case .night: return UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        }
    }
    var text: UIColor {
        switch self {
        case .paper: return UIColor(red: 0.13, green: 0.12, blue: 0.11, alpha: 1)
        case .sepia: return UIColor(red: 0.24, green: 0.17, blue: 0.10, alpha: 1)
        case .gray: return UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        case .night: return UIColor(red: 0.80, green: 0.78, blue: 0.74, alpha: 1)
        }
    }
    var isDark: Bool { self == .night }
    var name: String {
        switch self { case .paper: return "Бумага"; case .sepia: return "Сепия"; case .gray: return "Олива"; case .night: return "Ночь" }
    }
}

struct ReaderSettings: Equatable {
    var fontSize: CGFloat
    var theme: PaperTheme
    var lineSpacing: CGFloat
    var topInset: CGFloat
    var lockOrientation: Bool

    static func load() -> ReaderSettings {
        let d = UserDefaults.standard
        return ReaderSettings(
            fontSize: d.object(forKey: "rs.fontSize") as? CGFloat ?? 20,
            theme: PaperTheme(rawValue: d.integer(forKey: "rs.theme")) ?? .paper,
            lineSpacing: d.object(forKey: "rs.lineSpacing") as? CGFloat ?? 4,
            topInset: d.object(forKey: "rs.topInset") as? CGFloat ?? 20,
            lockOrientation: d.bool(forKey: "rs.lockOrientation"))
    }
    func save() {
        let d = UserDefaults.standard
        d.set(fontSize, forKey: "rs.fontSize")
        d.set(theme.rawValue, forKey: "rs.theme")
        d.set(lineSpacing, forKey: "rs.lineSpacing")
        d.set(topInset, forKey: "rs.topInset")
        d.set(lockOrientation, forKey: "rs.lockOrientation")
    }
}

// MARK: - Вёрстка главы в текст

struct ChapterText {
    let string: NSAttributedString
    let blockStarts: [Int]           // смещение начала каждого блока
    let anchors: [String: Int]       // id → смещение
}

enum Typesetter {
    static func font(size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
        let name: String
        switch (bold, italic) {
        case (true, true): name = "Literata-BoldItalic"
        case (true, false): name = "Literata-Bold"
        case (false, true): name = "Literata-Italic"
        default: name = "Literata-Regular"
        }
        if let f = UIFont(name: name, size: size) { return f }
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let base = UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
        if let d = base.fontDescriptor.withSymbolicTraits(traits) { return UIFont(descriptor: d, size: size) }
        return base
    }

    static func build(_ blocks: [Block], settings s: ReaderSettings, pageSize: CGSize) -> ChapterText {
        let out = NSMutableAttributedString()
        var starts: [Int] = []
        var anchors: [String: Int] = [:]
        let color = s.theme.text

        for (i, b) in blocks.enumerated() {
            let start = out.length
            starts.append(start)
            for a in b.anchors { anchors[a] = start }

            let para = NSMutableParagraphStyle()
            para.lineSpacing = s.lineSpacing
            para.hyphenationFactor = 0            // без переносов слов
            para.lineBreakStrategy = []
            var size = s.fontSize
            var forceBold = false
            var forceItalic = false

            switch b.kind {
            case .title(let lvl):
                size = s.fontSize * (lvl <= 1 ? 1.45 : lvl == 2 ? 1.3 : 1.15)
                forceBold = true
                para.alignment = .center
                para.paragraphSpacingBefore = i == 0 ? s.fontSize * 1.2 : s.fontSize * 2.2
                para.paragraphSpacing = s.fontSize * 1.4
            case .subtitle:
                para.alignment = .center
                forceBold = true
                para.paragraphSpacingBefore = s.fontSize * 0.8
                para.paragraphSpacing = s.fontSize * 0.8
            case .epigraph:
                forceItalic = true
                size = s.fontSize * 0.92
                para.alignment = .right
                para.headIndent = s.fontSize * 3
                para.firstLineHeadIndent = s.fontSize * 3
                para.paragraphSpacing = s.fontSize * 0.4
            case .poem:
                para.alignment = .left
                para.headIndent = s.fontSize * 2
                para.firstLineHeadIndent = s.fontSize * 2
            case .empty:
                para.paragraphSpacing = s.fontSize * 0.6
            case .image:
                para.alignment = .center
                para.paragraphSpacingBefore = s.fontSize * 0.6
                para.paragraphSpacing = s.fontSize * 0.6
            case .paragraph:
                para.alignment = .justified
                para.firstLineHeadIndent = s.fontSize * 1.4
            }

            if b.kind == .image {
                if let data = b.imageData, let img = UIImage(data: data) {
                    // картинка целиком помещается на страницу
                    let maxW = pageSize.width, maxH = pageSize.height * 0.85
                    let k = min(1, maxW / max(1, img.size.width), maxH / max(1, img.size.height))
                    let att = NSTextAttachment()
                    att.image = img
                    att.bounds = CGRect(x: 0, y: 0, width: floor(img.size.width * k), height: floor(img.size.height * k))
                    let a = NSMutableAttributedString(attachment: att)
                    a.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: a.length))
                    out.append(a)
                } else {
                    out.append(NSAttributedString(string: " ", attributes: [.font: font(size: size, bold: false, italic: false), .paragraphStyle: para]))
                }
            } else if b.kind == .empty {
                out.append(NSAttributedString(string: " ", attributes: [.font: font(size: size, bold: false, italic: false), .paragraphStyle: para]))
            } else {
                for r in b.runs {
                    out.append(NSAttributedString(string: r.text, attributes: [
                        .font: font(size: size, bold: r.bold || forceBold, italic: r.italic || forceItalic),
                        .foregroundColor: color,
                        .paragraphStyle: para
                    ]))
                }
            }
            if i < blocks.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: [.font: font(size: size, bold: false, italic: false), .paragraphStyle: para]))
            }
        }
        if out.length == 0 {
            out.append(NSAttributedString(string: " ", attributes: [.font: font(size: s.fontSize, bold: false, italic: false)]))
        }
        return ChapterText(string: out, blockStarts: starts, anchors: anchors)
    }
}

// MARK: - Разбивка главы на страницы
// Одна вёрстка на всю главу: каждая страница — свой «контейнер» общего текста.
// Поэтому абзац, перешедший на следующую страницу, продолжается без лишнего отступа,
// а выравнивание по ширине сохраняется до последней строки страницы.

final class ChapterPages {
    let text: ChapterText
    let storage: NSTextStorage
    let layout: NSLayoutManager
    private(set) var containers: [NSTextContainer] = []
    private(set) var ranges: [NSRange] = []

    init(text: ChapterText, pageSize: CGSize) {
        self.text = text
        storage = NSTextStorage(attributedString: text.string)
        layout = NSLayoutManager()
        layout.usesFontLeading = true
        storage.addLayoutManager(layout)
        var safety = 0
        while safety < 5000 {
            safety += 1
            let container = NSTextContainer(size: pageSize)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            let glyphs = layout.glyphRange(for: container)
            if glyphs.length == 0 {
                layout.removeTextContainer(at: layout.textContainers.count - 1)
                break
            }
            let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            containers.append(container)
            ranges.append(chars)
            if NSMaxRange(chars) >= storage.length { break }
        }
        if containers.isEmpty {
            let c = NSTextContainer(size: pageSize)
            c.lineFragmentPadding = 0
            layout.addTextContainer(c)
            containers = [c]
            ranges = [NSRange(location: 0, length: storage.length)]
        }
    }

    var count: Int { containers.count }

    func page(containing offset: Int) -> Int {
        for (i, r) in ranges.enumerated() where offset < NSMaxRange(r) { return i }
        return max(0, ranges.count - 1)
    }
}
