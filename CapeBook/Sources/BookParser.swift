import Foundation

// MARK: - Содержимое книги в простом виде

struct TextRun {
    var text: String
    var bold = false
    var italic = false
}

enum BlockKind: Equatable {
    case title(Int)       // заголовок (уровень 1...)
    case paragraph
    case subtitle
    case epigraph
    case poem
    case empty
    case image
}

struct Block {
    var kind: BlockKind
    var runs: [TextRun] = []
    var anchors: [String] = []      // id элементов, начинающихся в этом блоке (для оглавления)
    var imageData: Data? = nil      // для блока-картинки
    var plainText: String { runs.map { $0.text }.joined() }
}

struct TocEntry: Identifiable {
    let id = UUID()
    var title: String
    var chapter: Int
    var anchor: String?             // id внутри главы (EPUB) или nil — начало главы
    var block: Int?                 // номер блока (FB2)
    var level: Int
}

struct BookMeta {
    var title = ""
    var author = ""
    var cover: Data?
}

/// Загруженная книга: главы разбираются по требованию
protocol BookContent: AnyObject {
    var chapterCount: Int { get }
    var toc: [TocEntry] { get }
    func blocks(chapter: Int) -> [Block]
}

enum BookParser {
    static func metadata(url: URL, format: BookFormat) -> BookMeta {
        switch format {
        case .epub: return EpubBook(url: url)?.meta ?? BookMeta()
        case .fb2: return Fb2Book(url: url)?.meta ?? BookMeta()
        }
    }
    static func open(url: URL, format: BookFormat) -> BookContent? {
        switch format {
        case .epub: return EpubBook(url: url)
        case .fb2: return Fb2Book(url: url)
        }
    }
}

// MARK: - Сборка блоков из дерева (общая для EPUB и FB2)

struct BlockBuilder {
    var blocks: [Block] = []
    private var current: Block?
    private var pendingAnchors: [String] = []

    mutating func anchor(_ id: String?) {
        guard let id, !id.isEmpty else { return }
        if current != nil { current!.anchors.append(id) } else { pendingAnchors.append(id) }
    }
    mutating func begin(_ kind: BlockKind) {
        flush()
        current = Block(kind: kind, runs: [], anchors: pendingAnchors)
        pendingAnchors = []
    }
    mutating func text(_ s: String, bold: Bool, italic: Bool) {
        let collapsed = BlockBuilder.collapse(s)
        guard !collapsed.isEmpty else { return }
        if current == nil { begin(.paragraph) }
        if let last = current!.runs.last, last.bold == bold, last.italic == italic {
            current!.runs[current!.runs.count - 1].text += collapsed
        } else {
            current!.runs.append(TextRun(text: collapsed, bold: bold, italic: italic))
        }
    }
    mutating func image(_ data: Data?) {
        guard let data, data.count > 200 else { return }
        flush()
        blocks.append(Block(kind: .image, runs: [], anchors: pendingAnchors, imageData: data))
        pendingAnchors = []
    }
    mutating func lineBreak() {
        if current != nil { current!.runs.append(TextRun(text: "\u{2028}")) }
    }
    mutating func flush() {
        guard var b = current else { return }
        current = nil
        // убрать пробелы по краям
        if !b.runs.isEmpty {
            b.runs[0].text = String(b.runs[0].text.drop(while: { $0 == " " }))
            let li = b.runs.count - 1
            while b.runs[li].text.hasSuffix(" ") { b.runs[li].text.removeLast() }
        }
        if b.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && b.kind != .empty && b.kind != .image {
            pendingAnchors.append(contentsOf: b.anchors)   // пустой блок — якоря переходят к следующему
            return
        }
        blocks.append(b)
    }
    mutating func finish() -> [Block] {
        flush()
        if !pendingAnchors.isEmpty, !blocks.isEmpty { blocks[blocks.count - 1].anchors.append(contentsOf: pendingAnchors) }
        return blocks
    }
    static func collapse(_ s: String) -> String {
        var out = ""
        var space = false
        for ch in s {
            if ch == "\n" || ch == "\r" || ch == "\t" || ch == " " {
                if !space { out.append(" "); space = true }
            } else { out.append(ch); space = false }
        }
        return out
    }
}

// MARK: - EPUB

final class EpubBook: BookContent {
    let zip: ZipArchive
    var meta = BookMeta()
    var spine: [String] = []            // полные пути глав внутри архива
    var toc: [TocEntry] = []
    private var cache: [Int: [Block]] = [:]

    var chapterCount: Int { spine.count }

    init?(url: URL) {
        guard let z = ZipArchive(url: url) else { return nil }
        zip = z
        guard let cont = z.read("META-INF/container.xml"), let ctree = XMLTreeBuilder.parse(cont),
              let rootfile = ctree.find("rootfile"), let opfPath = rootfile.attrs["full-path"],
              let opfData = z.read(opfPath), let opf = XMLTreeBuilder.parse(opfData) else { return nil }
        let base = (opfPath as NSString).deletingLastPathComponent

        if let md = opf.find("metadata") {
            meta.title = md.find("title")?.innerText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            meta.author = md.findAll("creator").map { $0.innerText.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: ", ")
        }
        var items: [String: (href: String, type: String, props: String)] = [:]
        for it in opf.findAll("item") {
            if let id = it.attrs["id"], let href = it.attrs["href"] {
                items[id] = (EpubBook.join(base, href), it.attrs["media-type"] ?? "", it.attrs["properties"] ?? "")
            }
        }
        var tocNcxID: String?
        if let sp = opf.find("spine") {
            tocNcxID = sp.attrs["toc"]
            for ref in sp.all("itemref") {
                if let idref = ref.attrs["idref"], let it = items[idref] { spine.append(it.href) }
            }
        }
        // обложка
        var coverPath: String?
        if let c = items.values.first(where: { $0.props.contains("cover-image") }) { coverPath = c.href }
        if coverPath == nil {
            for m in opf.findAll("meta") where m.attrs["name"] == "cover" {
                if let id = m.attrs["content"], let it = items[id] { coverPath = it.href }
            }
        }
        if coverPath == nil, let c = items.first(where: { $0.key.lowercased().contains("cover") && $0.value.type.hasPrefix("image") }) {
            coverPath = c.value.href
        }
        if let cp = coverPath { meta.cover = z.read(cp) }

        // оглавление: EPUB 3 (nav) или EPUB 2 (ncx)
        if let nav = items.values.first(where: { $0.props.split(separator: " ").contains("nav") }) {
            parseNav(path: nav.href)
        }
        if toc.isEmpty {
            let ncx = tocNcxID.flatMap { items[$0]?.href } ?? items.values.first(where: { $0.type == "application/x-dtbncx+xml" })?.href
            if let ncx { parseNcx(path: ncx) }
        }
    }

    static func join(_ base: String, _ href: String) -> String {
        let h = href.removingPercentEncoding ?? href
        var parts = base.isEmpty ? [] : base.split(separator: "/").map(String.init)
        for comp in h.split(separator: "/").map(String.init) {
            if comp == ".." { if !parts.isEmpty { parts.removeLast() } }
            else if comp != "." { parts.append(comp) }
        }
        return parts.joined(separator: "/")
    }
    private func target(_ base: String, _ src: String) -> (Int, String?)? {
        let pieces = src.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let path = EpubBook.join(base, pieces[0])
        let anchor = pieces.count > 1 ? pieces[1] : nil
        guard let idx = spine.firstIndex(where: { $0.lowercased() == path.lowercased() }) else { return nil }
        return (idx, anchor)
    }
    private func parseNav(path: String) {
        guard let d = zip.read(path), let tree = XMLTreeBuilder.parse(d) else { return }
        let base = (path as NSString).deletingLastPathComponent
        var navs = tree.findAll("nav")
        if let tocNav = navs.first(where: { ($0.attrs["type"] ?? "").contains("toc") }) { navs = [tocNav] }
        guard let nav = navs.first, let ol = nav.find("ol") else { return }
        walkOl(ol, base: base, level: 1)
    }
    private func walkOl(_ ol: XNode, base: String, level: Int) {
        for li in ol.all("li") {
            if let a = li.find("a"), let href = a.attrs["href"], let t = target(base, href) {
                let title = BlockBuilder.collapse(a.innerText).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { toc.append(TocEntry(title: title, chapter: t.0, anchor: t.1, block: nil, level: level)) }
            }
            if let sub = li.first("ol") { walkOl(sub, base: base, level: level + 1) }
        }
    }
    private func parseNcx(path: String) {
        guard let d = zip.read(path), let tree = XMLTreeBuilder.parse(d), let map = tree.find("navmap") else { return }
        let base = (path as NSString).deletingLastPathComponent
        walkNavPoints(map, base: base, level: 1)
    }
    private func walkNavPoints(_ node: XNode, base: String, level: Int) {
        for np in node.all("navpoint") {
            let title = BlockBuilder.collapse(np.first("navlabel")?.innerText ?? "").trimmingCharacters(in: .whitespaces)
            if let src = np.first("content")?.attrs["src"], let t = target(base, src), !title.isEmpty {
                toc.append(TocEntry(title: title, chapter: t.0, anchor: t.1, block: nil, level: level))
            }
            walkNavPoints(np, base: base, level: level + 1)
        }
    }

    func blocks(chapter: Int) -> [Block] {
        if let c = cache[chapter] { return c }
        guard chapter >= 0, chapter < spine.count, let d = zip.read(spine[chapter]),
              let tree = XMLTreeBuilder.parse(d) else { return [] }
        var b = BlockBuilder()
        let body = tree.find("body") ?? tree
        let base = (spine[chapter] as NSString).deletingLastPathComponent
        let z = zip
        let loader: (String) -> Data? = { src in z.read(EpubBook.join(base, src.components(separatedBy: "#")[0])) }
        EpubBook.walk(body, &b, bold: false, italic: false, img: loader)
        let res = b.finish()
        cache[chapter] = res
        return res
    }

    private static let blockTags: Set<String> = ["p", "div", "li", "dt", "dd", "pre", "tr", "figcaption", "caption"]
    private static func walk(_ n: XNode, _ b: inout BlockBuilder, bold: Bool, italic: Bool, img: (String) -> Data?) {
        for c in n.children {
            if c.isText { b.text(c.text, bold: bold, italic: italic); continue }
            b.anchor(c.attrs["id"])
            switch c.name {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                let lvl = Int(String(c.name.dropFirst())) ?? 1
                b.begin(.title(lvl)); walk(c, &b, bold: bold, italic: italic, img: img); b.flush()
            case "blockquote":
                b.begin(.epigraph); walk(c, &b, bold: bold, italic: true, img: img); b.flush()
            case "br":
                b.lineBreak()
            case "b", "strong":
                walk(c, &b, bold: true, italic: italic, img: img)
            case "i", "em", "cite":
                walk(c, &b, bold: bold, italic: true, img: img)
            case "img":
                if let src = c.attrs["src"] { b.image(img(src)) }
            case "image":   // svg <image xlink:href=…>
                if let src = c.attrs["href"] { b.image(img(src)) }
            case "script", "style", "head", "title":
                continue
            case "svg":
                walk(c, &b, bold: bold, italic: italic, img: img)
            case "hr":
                b.begin(.empty); b.flush()
            default:
                if blockTags.contains(c.name) {
                    // div с вложенными абзацами — контейнер, иначе — абзац
                    let hasBlocks = c.children.contains { !$0.isText && (blockTags.contains($0.name) || $0.name.hasPrefix("h")) }
                    if hasBlocks { b.flush(); walk(c, &b, bold: bold, italic: italic, img: img); b.flush() }
                    else {
                        let cls = (c.attrs["class"] ?? "").lowercased()
                        let kind: BlockKind = cls.contains("title") || cls.contains("head") ? .title(2)
                            : cls.contains("epigraph") ? .epigraph : cls.contains("poem") || cls.contains("stanza") ? .poem : .paragraph
                        b.begin(kind); walk(c, &b, bold: bold, italic: italic, img: img); b.flush()
                    }
                } else {
                    walk(c, &b, bold: bold, italic: italic, img: img)   // section, span, a, body…
                }
            }
        }
    }
}

// MARK: - FB2

final class Fb2Book: BookContent {
    var meta = BookMeta()
    var toc: [TocEntry] = []
    private var chapters: [[Block]] = []
    var chapterCount: Int { chapters.count }
    private static var binaries: [String: String] = [:]   // id → base64 (на время разбора)

    init?(url: URL) {
        guard let d = try? Data(contentsOf: url), let tree = XMLTreeBuilder.parse(d) else { return nil }
        if let ti = tree.find("title-info") {
            meta.title = BlockBuilder.collapse(ti.first("book-title")?.innerText ?? "").trimmingCharacters(in: .whitespaces)
            meta.author = ti.all("author").map { a in
                ["first-name", "middle-name", "last-name"].compactMap { a.first($0)?.innerText.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }.joined(separator: " ")
            }.filter { !$0.isEmpty }.joined(separator: ", ")
            if let img = ti.find("coverpage")?.find("image"), let href = img.attrs["href"] {
                let id = href.hasPrefix("#") ? String(href.dropFirst()) : href
                for bin in tree.all("binary") where bin.attrs["id"] == id {
                    meta.cover = Data(base64Encoded: bin.innerText, options: .ignoreUnknownCharacters)
                }
            }
        }
        Fb2Book.binaries = [:]
        for bin in tree.all("binary") { if let id = bin.attrs["id"] { Fb2Book.binaries[id] = bin.innerText } }
        defer { Fb2Book.binaries = [:] }
        // основной текст — первый body без name="notes"
        let bodies = tree.all("body")
        guard let body = bodies.first(where: { ($0.attrs["name"] ?? "") != "notes" }) ?? bodies.first else { return }
        let sections = body.all("section")
        if sections.isEmpty {
            var b = BlockBuilder(); Fb2Book.walk(body, &b, level: 1, bold: false, italic: false)
            chapters = [b.finish()]
        } else {
            // всё до первой секции (заголовок книги, эпиграф) — отдельная глава
            var pre = BlockBuilder()
            for c in body.children where c.name != "section" { Fb2Book.walkOne(c, &pre, level: 1, bold: false, italic: false) }
            let preBlocks = pre.finish()
            if !preBlocks.isEmpty { chapters.append(preBlocks) }
            for s in sections {
                let idx = chapters.count
                var b = BlockBuilder()
                Fb2Book.walkOne(s, &b, level: 1, bold: false, italic: false)
                let blocks = b.finish()
                chapters.append(blocks)
                // оглавление: заголовки всех уровней внутри главы
                for (bi, bl) in blocks.enumerated() {
                    if case .title(let lvl) = bl.kind {
                        let t = bl.plainText.replacingOccurrences(of: "\u{2028}", with: " ").trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { toc.append(TocEntry(title: t, chapter: idx, anchor: nil, block: bi, level: lvl)) }
                    }
                }
            }
        }
    }

    func blocks(chapter: Int) -> [Block] { chapter >= 0 && chapter < chapters.count ? chapters[chapter] : [] }

    private static func walk(_ n: XNode, _ b: inout BlockBuilder, level: Int, bold: Bool, italic: Bool) {
        for c in n.children { walkOne(c, &b, level: level, bold: bold, italic: italic) }
    }
    private static func walkOne(_ c: XNode, _ b: inout BlockBuilder, level: Int, bold: Bool, italic: Bool) {
        if c.isText { b.text(c.text, bold: bold, italic: italic); return }
        b.anchor(c.attrs["id"])
        switch c.name {
        case "section":
            b.flush(); walk(c, &b, level: level + 1, bold: bold, italic: italic); b.flush()
        case "title":
            // строки заголовка — одним блоком через перенос строки
            b.begin(.title(max(1, level - 1)))
            var first = true
            for p in c.children where !p.isText {
                if !first { b.lineBreak() }
                walk(p, &b, level: level, bold: bold, italic: italic)
                first = false
            }
            b.flush()
        case "p", "text-author":
            b.begin(.paragraph); walk(c, &b, level: level, bold: bold, italic: italic); b.flush()
        case "subtitle":
            b.begin(.subtitle); walk(c, &b, level: level, bold: bold, italic: italic); b.flush()
        case "epigraph", "cite", "annotation":
            for p in c.children where !p.isText {
                b.begin(.epigraph); walk(p, &b, level: level, bold: bold, italic: true); b.flush()
            }
        case "poem", "stanza":
            walk(c, &b, level: level, bold: bold, italic: italic)
        case "v":
            b.begin(.poem); walk(c, &b, level: level, bold: bold, italic: italic); b.flush()
        case "empty-line":
            b.begin(.empty); b.flush()
        case "strong":
            walk(c, &b, level: level, bold: true, italic: italic)
        case "emphasis":
            walk(c, &b, level: level, bold: bold, italic: true)
        case "image":
            if let href = c.attrs["href"] {
                let id = href.hasPrefix("#") ? String(href.dropFirst()) : href
                if let b64 = binaries[id] { b.image(Data(base64Encoded: b64, options: .ignoreUnknownCharacters)) }
            }
        case "binary", "table":
            return
        default:
            walk(c, &b, level: level, bold: bold, italic: italic)
        }
    }
}
