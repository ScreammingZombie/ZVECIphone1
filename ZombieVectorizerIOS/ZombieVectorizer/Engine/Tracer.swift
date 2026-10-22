import Foundation

/// Tabla arista -> segmentos (direccionamiento abierto).
final class EdgeTable {
    var keys: [Int32]
    var v1: [Int32]
    var v2: [Int32]
    let mask: Int

    init(segments: Int) {
        var cap = 1
        while cap < segments * 4 { cap <<= 1 }
        mask = cap - 1
        keys = [Int32](repeating: -1, count: cap)
        v1 = [Int32](repeating: -1, count: cap)
        v2 = [Int32](repeating: -1, count: cap)
    }

    @inline(__always) func slot(_ k: Int32) -> Int {
        var s = Int((UInt32(bitPattern: k) &* 2_654_435_761) >> 7) & mask
        while keys[s] != -1 && keys[s] != k { s = (s + 1) & mask }
        return s
    }
}

/// Traza el contorno (marching squares sobre una máscara suavizada) de las etiquetas >= j
/// y lo ajusta con curvas Bézier.
enum Tracer {
    static func trace(labels: [UInt8], w: Int, h: Int, j: Int, x0: Int, y0: Int, x1: Int, y1: Int,
                      A: inout [Float], B: inout [Float], passes: Int, err2: Double, win: Double,
                      cornerDeg: Double, minArea: Double, cancelled: () -> Bool) throws -> [[Float]] {
        let rx0 = max(x0 - 3, -3), rx1 = min(x1 + 3, w + 2)
        let ry0 = max(y0 - 3, -3), ry1 = min(y1 + 3, h + 2)
        let RW = rx1 - rx0 + 1, RH = ry1 - ry0 + 1

        // 1) máscara binaria (borde replicado + anillo de ceros para cerrar siempre los contornos)
        for ry in 0..<RH {
            let iy = ry + ry0
            let base = ry * RW
            if iy < -2 || iy > h + 1 {
                for k in 0..<RW { A[base + k] = 0 }
                continue
            }
            let row = min(max(iy, 0), h - 1) * w
            for rxi in 0..<RW {
                let ix = rxi + rx0
                if ix < -2 || ix > w + 1 {
                    A[base + rxi] = 0
                } else {
                    let l = Int(labels[row + min(max(ix, 0), w - 1)])
                    A[base + rxi] = (l >= j && l < 255) ? 1 : 0
                }
            }
        }
        // 2) suavizado [1 2 1]/4 separable
        for _ in 0..<passes {
            for y in 0..<RH {
                let b = y * RW
                for x in 0..<RW {
                    let l: Float = x > 0 ? A[b + x - 1] : 0
                    let r: Float = x < RW - 1 ? A[b + x + 1] : 0
                    B[b + x] = 0.25 * l + 0.5 * A[b + x] + 0.25 * r
                }
            }
            for y in 0..<RH {
                let b = y * RW
                for x in 0..<RW {
                    let u: Float = y > 0 ? B[b - RW + x] : 0
                    let d: Float = y < RH - 1 ? B[b + RW + x] : 0
                    A[b + x] = 0.25 * u + 0.5 * B[b + x] + 0.25 * d
                }
            }
        }

        // 3) marching squares -> segmentos entre aristas
        var sa: [Int32] = []
        var sb: [Int32] = []
        sa.reserveCapacity(4096); sb.reserveCapacity(4096)
        func seg(_ a: Int, _ b: Int) { sa.append(Int32(a)); sb.append(Int32(b)) }
        for y in 0..<(RH - 1) {
            if (y & 127) == 0 && cancelled() { throw CancelledError() }
            for x in 0..<(RW - 1) {
                let i = y * RW + x
                let tl = A[i], tr = A[i + 1], bl = A[i + RW], br = A[i + RW + 1]
                var idx = 0
                if tl >= 0.5 { idx |= 8 }
                if tr >= 0.5 { idx |= 4 }
                if br >= 0.5 { idx |= 2 }
                if bl >= 0.5 { idx |= 1 }
                if idx == 0 || idx == 15 { continue }
                let top = 2 * i, bottom = 2 * (i + RW), left = 2 * i + 1, right = 2 * (i + 1) + 1
                switch idx {
                case 1, 14: seg(left, bottom)
                case 2, 13: seg(bottom, right)
                case 3, 12: seg(left, right)
                case 4, 11: seg(top, right)
                case 6, 9: seg(top, bottom)
                case 7, 8: seg(top, left)
                case 5:
                    if (tl + tr + bl + br) * 0.25 >= 0.5 { seg(top, left); seg(bottom, right) }
                    else { seg(top, right); seg(left, bottom) }
                case 10:
                    if (tl + tr + bl + br) * 0.25 >= 0.5 { seg(top, right); seg(left, bottom) }
                    else { seg(top, left); seg(bottom, right) }
                default: break
                }
            }
        }
        let S = sa.count
        if S < 4 { return [] }

        // 4) tabla arista -> segmentos
        let table = EdgeTable(segments: S)
        for s in 0..<S {
            for e in [sa[s], sb[s]] {
                let sl = table.slot(e)
                if table.keys[sl] == -1 { table.keys[sl] = e }
                if table.v1[sl] == -1 { table.v1[sl] = Int32(s) } else { table.v2[sl] = Int32(s) }
            }
        }

        // 5) recorrer lazos, convertir a puntos y ajustar curvas
        var used = [Bool](repeating: false, count: S)
        var result: [[Float]] = []
        var pts: [Int32] = []
        pts.reserveCapacity(4096)
        var loops = 0
        let fw = Float(w), fh = Float(h)
        for s in 0..<S {
            if used[s] { continue }
            used[s] = true
            loops += 1
            if (loops & 63) == 0 && cancelled() { throw CancelledError() }
            pts.removeAll(keepingCapacity: true)
            let startE = sa[s]
            var cur = sb[s]
            var segId = Int32(s)
            pts.append(startE)
            var ok = true
            while cur != startE {
                pts.append(cur)
                let sl = table.slot(cur)
                let o = table.v1[sl] == segId ? table.v2[sl] : table.v1[sl]
                if o < 0 || used[Int(o)] { ok = false; break }
                used[Int(o)] = true
                cur = sa[Int(o)] == cur ? sb[Int(o)] : sa[Int(o)]
                segId = o
            }
            if !ok || pts.count < 4 { continue }

            let m = pts.count
            var xs = [Double](repeating: 0, count: m)
            var ys = [Double](repeating: 0, count: m)
            var n = 0
            for q in 0..<m {
                let id = Int(pts[q])
                let e = id >> 1
                let ex = e % RW, ey = e / RW
                var fx: Float, fy: Float
                if (id & 1) == 0 {
                    let f0 = A[e], f1 = A[e + 1]
                    fx = Float(ex) + (0.5 - f0) / (f1 - f0); fy = Float(ey)
                } else {
                    let f0 = A[e], f1 = A[e + RW]
                    fx = Float(ex); fy = Float(ey) + (0.5 - f0) / (f1 - f0)
                }
                let px = Double(min(max(Float(rx0) + fx + 0.5, 0), fw))
                let py = Double(min(max(Float(ry0) + fy + 0.5, 0), fh))
                if n > 0 && abs(px - xs[n - 1]) < 1e-3 && abs(py - ys[n - 1]) < 1e-3 { continue }
                xs[n] = px; ys[n] = py; n += 1
            }
            while n > 1 && abs(xs[n - 1] - xs[0]) < 1e-3 && abs(ys[n - 1] - ys[0]) < 1e-3 { n -= 1 }
            if n < 4 { continue }
            var area = 0.0
            for q in 0..<n {
                let r = (q + 1) % n
                area += xs[q] * ys[r] - xs[r] * ys[q]
            }
            if abs(area) * 0.5 < minArea { continue }
            if let c = Fitter(x: xs, y: ys, n: n, err2: err2, cornerWin: win, cornerDeg: cornerDeg).fitClosed(), c.count >= 8 {
                result.append(c)
            }
        }
        return result
    }
}
