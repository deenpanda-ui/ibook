import Foundation

/// Простое дерево XML: удобнее, чем событийный разбор, для книг небольшого объёма.
final class XNode {
    let name: String              // имя без префикса пространства имён, в нижнем регистре
    var attrs: [String: String]   // имена атрибутов тоже без префикса, в нижнем регистре
    var children: [XNode] = []
    var text: String = ""         // текст — только у текстовых узлов (name == "#text")
    weak var parent: XNode?

    init(name: String, attrs: [String: String] = [:]) { self.name = name; self.attrs = attrs }

    var isText: Bool { name == "#text" }

    func first(_ n: String) -> XNode? { children.first { $0.name == n } }
    func all(_ n: String) -> [XNode] { children.filter { $0.name == n } }

    /// Поиск в глубину первого узла с таким именем
    func find(_ n: String) -> XNode? {
        for c in children {
            if c.name == n { return c }
            if let f = c.find(n) { return f }
        }
        return nil
    }
    func findAll(_ n: String, into out: inout [XNode]) {
        for c in children {
            if c.name == n { out.append(c) }
            c.findAll(n, into: &out)
        }
    }
    func findAll(_ n: String) -> [XNode] { var r: [XNode] = []; findAll(n, into: &r); return r }

    /// Весь текст внутри узла
    var innerText: String {
        if isText { return text }
        return children.map { $0.innerText }.joined()
    }
}

final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    private var stack: [XNode] = []
    private(set) var root: XNode?

    private static func local(_ s: String) -> String {
        if let i = s.lastIndex(of: ":") { return String(s[s.index(after: i)...]).lowercased() }
        return s.lowercased()
    }

    static func parse(_ data: Data) -> XNode? {
        let b = XMLTreeBuilder()
        let p = XMLParser(data: XMLTreeBuilder.fixEntities(data))
        p.shouldProcessNamespaces = false
        p.shouldResolveExternalEntities = false
        p.delegate = b
        _ = p.parse()          // даже при ошибке оставляем то, что успели разобрать
        return b.root
    }

    // XHTML часто содержит &nbsp; и другие именованные сущности, которых XML не знает
    private static let entities: [String: String] = [
        "nbsp": "&#160;", "mdash": "&#8212;", "ndash": "&#8211;", "laquo": "&#171;", "raquo": "&#187;",
        "hellip": "&#8230;", "shy": "", "ldquo": "&#8220;", "rdquo": "&#8221;", "bdquo": "&#8222;",
        "lsquo": "&#8216;", "rsquo": "&#8217;", "copy": "&#169;", "reg": "&#174;", "trade": "&#8482;",
        "times": "&#215;", "middot": "&#183;", "bull": "&#8226;", "deg": "&#176;", "sect": "&#167;",
        "thinsp": "&#8201;", "ensp": "&#8194;", "emsp": "&#8195;", "zwnj": "", "zwj": "", "euro": "&#8364;",
        "minus": "&#8722;", "prime": "&#8242;", "frac12": "&#189;", "frac14": "&#188;", "para": "&#182;"
    ]
    private static func fixEntities(_ data: Data) -> Data {
        guard var s = String(data: data, encoding: .utf8) else { return data }
        guard s.contains("&") else { return data }
        let re = try? NSRegularExpression(pattern: "&([a-zA-Z][a-zA-Z0-9]*);")
        guard let re else { return data }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            switch name {
            case "amp", "lt", "gt", "quot", "apos": out += ns.substring(with: m.range)
            default: out += entities[name.lowercased()] ?? " "
            }
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        s = out
        return s.data(using: .utf8) ?? data
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        var a: [String: String] = [:]
        for (k, v) in attributeDict { a[XMLTreeBuilder.local(k)] = v }
        let n = XNode(name: XMLTreeBuilder.local(elementName), attrs: a)
        if let top = stack.last { n.parent = top; top.children.append(n) } else { root = n }
        stack.append(n)
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if !stack.isEmpty { stack.removeLast() }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let top = stack.last else { return }
        if let lastChild = top.children.last, lastChild.isText { lastChild.text += string; return }
        let t = XNode(name: "#text"); t.text = string; t.parent = top
        top.children.append(t)
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let s = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: s) }
    }
}
