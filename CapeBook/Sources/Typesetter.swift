import UIKit

// MARK: - Настройки чтения

enum PaperTheme: Int, CaseIterable {
    // номера совпадают с прежними темами, чтобы сохранённый выбор не сбился
    case light = 0, cream = 1, olive = 2, night = 3

    var name: String {
        switch self {
        case .light: return "Светлая бумага"
        case .cream: return "Кремовая бумага"
        case .olive: return "Оливковая"
        case .night: return "Ночная"
        }
    }
    var imageName: String {
        switch self {
        case .light: return "paper_light"
        case .cream: return "paper_cream"
        case .olive: return "paper_olive"
        case .night: return "paper_night"
        }
    }
    /// фон-картинка (ваши обои) и средний цвет на случай, если картинки нет
    var image: UIImage? { UIImage(named: imageName + ".jpg") ?? UIImage(named: imageName) }
    var background: UIColor {
        switch self {
        case .light: return UIColor(red: 219/255, green: 208/255, blue: 195/255, alpha: 1)
        case .cream: return UIColor(red: 247/255, green: 229/255, blue: 203/255, alpha: 1)
        case .olive: return UIColor(red: 103/255, green: 106/255, blue: 81/255, alpha: 1)
        case .night: return UIColor(red: 36/255, green: 36/255, blue: 36/255, alpha: 1)
        }
    }
    var text: UIColor {
        switch self {
        case .light: return UIColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1)
        case .cream: return UIColor(red: 0.20, green: 0.15, blue: 0.10, alpha: 1)
        case .olive: return UIColor(red: 0.05, green: 0.06, blue: 0.04, alpha: 1)
        case .night: return UIColor(red: 0.80, green: 0.78, blue: 0.74, alpha: 1)
        }
    }
    var isDark: Bool { self == .night }
}

/// Шрифты для чтения (как в прежнем приложении + Literata)
enum ReaderFonts {
    static let all: [(family: String, title: String)] = [
        ("Literata", "Literata"),
        ("Georgia", "Georgia"),
        ("Times New Roman", "Times New Roman"),
        ("Baskerville", "Baskerville"),
        ("Palatino", "Palatino"),
        ("Charter", "Charter"),
        ("Iowan Old Style", "Iowan Old Style"),
        ("Verdana", "Verdana"),
        ("Trebuchet MS", "Trebuchet"),
        ("Arial", "Arial"),
        ("Helvetica Neue", "Helvetica")
    ]
}

struct ReaderSettings: Equatable {
    var fontFamily: String
    var fontSize: CGFloat
    var theme: PaperTheme
    var lineSpacing: CGFloat
    var topInset: CGFloat
    var lockOrientation: Bool

    static func load() -> ReaderSettings {
        let d = UserDefaults.standard
        return ReaderSettings(
            fontFamily: d.string(forKey: "rs.fontFamily") ?? "Literata",
            fontSize: d.object(forKey: "rs.fontSize") as? CGFloat ?? 20,
            theme: PaperTheme(rawValue: d.integer(forKey: "rs.theme")) ?? .light,
            lineSpacing: d.object(forKey: "rs.lineSpacing") as? CGFloat ?? 4,
            topInset: d.object(forKey: "rs.topInset") as? CGFloat ?? 20,
            lockOrientation: d.bool(forKey: "rs.lockOrientation"))
    }
    func save() {
        let d = UserDefaults.standard
        d.set(fontFamily, forKey: "rs.fontFamily")
        d.set(fontSize, forKey: "rs.fontSize")
        d.set(theme.rawValue, forKey: "rs.theme")
        d.set(lineSpacing, forKey: "rs.lineSpacing")
        d.set(topInset, forKey: "rs.topInset")
        d.set(lockOrientation, forKey: "rs.lockOrientation")
    }
}

extension NSAttributedString.Key {
    /// абзац, который нужно выровнять по ширине
    static let ikJustify = NSAttributedString.Key("ik.justify")
}

// MARK: - Выравнивание по ширине только за счёт пробелов
// Системное выравнивание в iOS 26 раздвигает и сами буквы («П р е д п о л о ж и м»).
// Здесь строки сначала верстаются по левому краю, затем недостающая ширина
// делится между пробелами строки — как в классических книгах и в прежнем приложении.
func justifyByWordSpacing(_ storage: NSTextStorage, width: CGFloat) {
    let lm = NSLayoutManager()
    let tc = NSTextContainer(size: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
    tc.lineFragmentPadding = 0
    lm.addTextContainer(tc)
    storage.addLayoutManager(lm)
    defer { storage.removeLayoutManager(lm) }
    lm.ensureLayout(for: tc)
    let ns = storage.string as NSString
    var adjust: [(Int, CGFloat)] = []
    var g = 0
    let total = lm.numberOfGlyphs
    while g < total {
        var lineGlyphs = NSRange(location: 0, length: 0)
        let lineRect = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: &lineGlyphs)
        g = max(g + 1, NSMaxRange(lineGlyphs))
        let chars = lm.characterRange(forGlyphRange: lineGlyphs, actualGlyphRange: nil)
        guard chars.length > 1, NSMaxRange(chars) < ns.length else { continue }       // последняя строка текста
        guard storage.attribute(.ikJustify, at: chars.location, effectiveRange: nil) != nil else { continue }
        let last = ns.character(at: NSMaxRange(chars) - 1)
        if last == 10 || last == 0x2028 { continue }                                 // последняя строка абзаца
        var end = NSMaxRange(chars)
        while end > chars.location, ns.character(at: end - 1) == 32 { end -= 1 }
        guard end > chars.location else { continue }
        var spaces: [Int] = []
        for i in chars.location..<end where ns.character(at: i) == 32 { spaces.append(i) }
        guard !spaces.isEmpty else { continue }
        let glyphs = lm.glyphRange(forCharacterRange: NSRange(location: chars.location, length: end - chars.location), actualCharacterRange: nil)
        let used = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        let extra = lineRect.maxX - used.maxX - 0.5
        guard extra > 0.5, extra < width * 0.45 else { continue }
        let per = extra / CGFloat(spaces.count)
        for i in spaces { adjust.append((i, per)) }
    }
    guard !adjust.isEmpty else { return }
    storage.beginEditing()
    for (i, k) in adjust { storage.addAttribute(.kern, value: k, range: NSRange(location: i, length: 1)) }
    storage.endEditing()
}

// MARK: - Вёрстка главы в текст

struct ChapterText {
    let string: NSAttributedString
    let blockStarts: [Int]           // смещение начала каждого блока
    let anchors: [String: Int]       // id → смещение
}

enum Typesetter {
    static var family = "Literata"

    static func font(size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
        if family == "Literata" {
            let name: String
            switch (bold, italic) {
            case (true, true): name = "Literata-BoldItalic"
            case (true, false): name = "Literata-Bold"
            case (false, true): name = "Literata-Italic"
            default: name = "Literata-Regular"
            }
            if let f = UIFont(name: name, size: size) { return f }
        }
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let desc = UIFontDescriptor(fontAttributes: [.family: family == "Literata" ? "Georgia" : family])
        let base = UIFont(descriptor: desc, size: size)
        if let d = base.fontDescriptor.withSymbolicTraits(traits) { return UIFont(descriptor: d, size: size) }
        return base
    }

    static func build(_ blocks: [Block], settings s: ReaderSettings, pageSize: CGSize) -> ChapterText {
        family = s.fontFamily
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
                para.alignment = .natural          // по ширине выравниваем сами — только пробелами (см. justifyByWordSpacing)
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
                    var attrs: [NSAttributedString.Key: Any] = [
                        .font: font(size: size, bold: r.bold || forceBold, italic: r.italic || forceItalic),
                        .foregroundColor: color,
                        .paragraphStyle: para
                    ]
                    if b.kind == .paragraph { attrs[.ikJustify] = true }
                    out.append(NSAttributedString(string: r.text, attributes: attrs))
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
        justifyByWordSpacing(storage, width: pageSize.width)
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
