import Foundation
import Compression

/// Минимальное чтение ZIP (EPUB — это ZIP-архив). Поддерживаются «без сжатия» и deflate.
final class ZipArchive {
    struct Entry {
        let name: String
        let method: Int
        let compressedSize: Int
        let size: Int
        let localHeaderOffset: Int
    }

    let data: Data
    private(set) var entries: [String: Entry] = [:]

    init?(url: URL) {
        guard let d = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        data = d
        if !readCentralDirectory() { return nil }
    }

    private func byte(_ o: Int) -> Int { Int(data[data.startIndex + o]) }
    private func u16(_ o: Int) -> Int { byte(o) | (byte(o + 1) << 8) }
    private func u32(_ o: Int) -> Int { u16(o) | (u16(o + 2) << 16) }

    private func readCentralDirectory() -> Bool {
        let n = data.count
        guard n >= 22 else { return false }
        var eocd = -1
        var i = n - 22
        let stop = max(0, n - 22 - 65_535)
        while i >= stop {
            if u32(i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return false }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        for _ in 0..<count {
            guard p + 46 <= n, u32(p) == 0x0201_4b50 else { break }
            let method = u16(p + 10)
            let csize = u32(p + 20)
            let usize = u32(p + 24)
            let nameLen = u16(p + 28)
            let extraLen = u16(p + 30)
            let commentLen = u16(p + 32)
            let local = u32(p + 42)
            guard p + 46 + nameLen <= n else { break }
            let nameData = data.subdata(in: (data.startIndex + p + 46)..<(data.startIndex + p + 46 + nameLen))
            let name = String(decoding: nameData, as: UTF8.self)
            entries[name] = Entry(name: name, method: method, compressedSize: csize, size: usize, localHeaderOffset: local)
            p += 46 + nameLen + extraLen + commentLen
        }
        return !entries.isEmpty
    }

    func entry(_ path: String) -> Entry? {
        if let e = entries[path] { return e }
        let low = path.lowercased()
        return entries.first(where: { $0.key.lowercased() == low })?.value
    }

    func read(_ path: String) -> Data? {
        guard let e = entry(path) else { return nil }
        let lh = e.localHeaderOffset
        guard lh + 30 <= data.count, u32(lh) == 0x0403_4b50 else { return nil }
        let start = lh + 30 + u16(lh + 26) + u16(lh + 28)
        guard start + e.compressedSize <= data.count else { return nil }
        let comp = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + e.compressedSize))
        switch e.method {
        case 0: return comp
        case 8: return inflate(comp, expected: e.size)
        default: return nil
        }
    }

    private func inflate(_ src: Data, expected: Int) -> Data? {
        guard !src.isEmpty else { return Data() }
        let cap = max(expected, 1024)
        var dst = Data(count: cap)
        let written: Int = dst.withUnsafeMutableBytes { (d: UnsafeMutableRawBufferPointer) -> Int in
            src.withUnsafeBytes { (s: UnsafeRawBufferPointer) -> Int in
                guard let dp = d.bindMemory(to: UInt8.self).baseAddress,
                      let sp = s.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dp, cap, sp, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        dst.count = written
        return dst
    }
}
