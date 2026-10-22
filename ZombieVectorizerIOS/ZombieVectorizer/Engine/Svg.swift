import Foundation

enum Svg {
    private static func n(_ f: Float) -> String {
        let r = (f * 100).rounded() / 100
        if r == r.rounded() { return String(Int(r)) }
        return String(r)
    }

    private static func straight(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float,
                                 _ x2: Float, _ y2: Float, _ x3: Float, _ y3: Float) -> Bool {
        let dx = x3 - x0, dy = y3 - y0
        let len = (dx * dx + dy * dy).squareRoot()
        if len < 1e-3 { return false }
        let d1 = abs((x1 - x0) * dy - (y1 - y0) * dx) / len
        let d2 = abs((x2 - x0) * dy - (y2 - y0) * dx) / len
        return d1 < 0.02 && d2 < 0.02
    }

    static func write(_ v: VectorImage) -> String {
        var s = String()
        s.reserveCapacity(1 << 20)
        s += "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(v.width) \(v.height)\" width=\"\(v.width)\" height=\"\(v.height)\""
        if v.transparent { s += " data-zv-transparent=\"1\"" }
        s += ">\n"
        for l in v.layers {
            s += "<path fill=\"#" + String(format: "%06X", UInt32(l.color & 0xFFFFFF)) + "\" fill-rule=\"evenodd\" d=\""
            for c in l.contours {
                s += "M" + n(c[0]) + " " + n(c[1])
                var px = c[0], py = c[1]
                var i = 2
                while i + 5 < c.count {
                    let x = c[i + 4], y = c[i + 5]
                    if straight(px, py, c[i], c[i + 1], c[i + 2], c[i + 3], x, y) {
                        s += "L" + n(x) + " " + n(y)
                    } else {
                        s += "C" + n(c[i]) + " " + n(c[i + 1]) + " " + n(c[i + 2]) + " " + n(c[i + 3]) + " " + n(x) + " " + n(y)
                    }
                    px = x; py = y
                    i += 6
                }
                s += "Z"
            }
            s += "\"/>\n"
        }
        s += "</svg>\n"
        return s
    }

    // ---------------------------------------------------------------- lectura (historial)
    private static func find(_ b: [UInt8], _ pattern: String, _ from: Int) -> Int? {
        let p = Array(pattern.utf8)
        if p.isEmpty || b.count < p.count { return nil }
        var i = from
        let last = b.count - p.count
        while i <= last {
            if b[i] == p[0] {
                var ok = true
                var k = 1
                while k < p.count { if b[i + k] != p[k] { ok = false; break }; k += 1 }
                if ok { return i }
            }
            i += 1
        }
        return nil
    }

    private static func intAttr(_ head: String, _ name: String) -> Int? {
        guard let r = head.range(of: " \(name)=\"") else { return nil }
        let digits = head[r.upperBound...].prefix(while: { $0.isNumber })
        return Int(digits)
    }

    /// Lee un SVG generado por `write`.
    static func parse(_ data: Data) throws -> VectorImage {
        let b = [UInt8](data)
        guard let s0 = find(b, "<svg", 0), let s1 = find(b, ">", s0) else { throw SvgError() }
        let head = String(decoding: b[s0...s1], as: UTF8.self)
        guard let w = intAttr(head, "width"), let h = intAttr(head, "height") else { throw SvgError() }
        let transparent = head.contains("data-zv-transparent")
        var layers: [Layer] = []
        var pos = s1
        while let ps = find(b, "<path fill=\"#", pos) {
            let hexStart = ps + 13
            if hexStart + 6 > b.count { break }
            let hex = String(decoding: b[hexStart..<(hexStart + 6)], as: UTF8.self)
            guard let rgb = UInt32(hex, radix: 16),
                  let d0 = find(b, " d=\"", hexStart) else { break }
            let dStart = d0 + 4
            guard let dEnd = find(b, "\"", dStart) else { break }
            layers.append(Layer(color: 0xFF00_0000 | rgb, contours: parseD(b, dStart, dEnd)))
            pos = dEnd
        }
        return VectorImage(width: w, height: h, layers: layers, transparent: transparent)
    }

    private static func parseD(_ b: [UInt8], _ from: Int, _ to: Int) -> [[Float]] {
        var out: [[Float]] = []
        var cur: [Float] = []
        var i = from

        func num() -> Float {
            while i < to && (b[i] == 32 || b[i] == 44) { i += 1 }
            var neg = false
            if i < to && b[i] == 45 { neg = true; i += 1 }
            var v: Double = 0
            while i < to && b[i] >= 48 && b[i] <= 57 { v = v * 10 + Double(b[i] - 48); i += 1 }
            if i < to && b[i] == 46 {
                i += 1
                var f = 0.1
                while i < to && b[i] >= 48 && b[i] <= 57 { v += Double(b[i] - 48) * f; f *= 0.1; i += 1 }
            }
            return Float(neg ? -v : v)
        }

        var px: Float = 0, py: Float = 0
        while i < to {
            switch b[i] {
            case 77: // M
                i += 1
                px = num(); py = num()
                cur.removeAll(keepingCapacity: true)
                cur.append(px); cur.append(py)
            case 76: // L
                i += 1
                let x = num(), y = num()
                cur.append(px + (x - px) / 3); cur.append(py + (y - py) / 3)
                cur.append(px + 2 * (x - px) / 3); cur.append(py + 2 * (y - py) / 3)
                cur.append(x); cur.append(y)
                px = x; py = y
            case 67: // C
                i += 1
                for _ in 0..<6 { cur.append(num()) }
                px = cur[cur.count - 2]; py = cur[cur.count - 1]
            case 90: // Z
                i += 1
                if cur.count >= 8 { out.append(cur) }
                cur.removeAll(keepingCapacity: true)
            default:
                i += 1
            }
        }
        return out
    }
}
