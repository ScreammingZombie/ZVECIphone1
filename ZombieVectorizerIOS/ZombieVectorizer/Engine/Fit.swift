import Foundation

/// Ajuste de curvas Bézier cúbicas (algoritmo de Schneider) con detección de esquinas.
final class Fitter {
    private let x: [Double]
    private let y: [Double]
    private let n: Int
    private let err2: Double
    private let cornerWin: Double
    private let cornerDeg: Double
    private var out: [Float] = []

    init(x: [Double], y: [Double], n: Int, err2: Double, cornerWin: Double, cornerDeg: Double) {
        self.x = x; self.y = y; self.n = n
        self.err2 = err2; self.cornerWin = cornerWin; self.cornerDeg = cornerDeg
        out.reserveCapacity(512)
    }

    func fitClosed() -> [Float]? {
        if n < 4 { return nil }
        let corners = findCorners()
        var idx: [Int] = []
        for i in 0..<n where corners[i] { idx.append(i) }
        if idx.isEmpty {
            // curva suave cerrada: se parte en dos mitades con tangentes continuas
            let m = n / 2
            let d0 = dir(n - 1, 1)
            let dm = dir(m - 1, m + 1)
            out.append(Float(x[0])); out.append(Float(y[0]))
            fitRun(0, m, d0.0, d0.1, -dm.0, -dm.1)
            fitRun(m, n, dm.0, dm.1, -d0.0, -d0.1)
        } else {
            out.append(Float(x[idx[0]])); out.append(Float(y[idx[0]]))
            for c in 0..<idx.count {
                let s = idx[c]
                var e = idx[(c + 1) % idx.count]
                if e <= s { e += n }
                if idx.count == 1 {
                    let m = s + n / 2
                    let tOut = tangentForward(s)
                    let tIn = tangentBackward(s + n)
                    let dm = dir((m - 1) % n, (m + 1) % n)
                    fitRun(s, m, tOut.0, tOut.1, -dm.0, -dm.1)
                    fitRun(m, s + n, dm.0, dm.1, tIn.0, tIn.1)
                } else {
                    let tOut = tangentForward(s)
                    let tIn = tangentBackward(e)
                    fitRun(s, e, tOut.0, tOut.1, tIn.0, tIn.1)
                }
            }
        }
        return out
    }

    // ---- índices cíclicos ----
    @inline(__always) private func px(_ i: Int) -> Double { x[((i % n) + n) % n] }
    @inline(__always) private func py(_ i: Int) -> Double { y[((i % n) + n) % n] }

    private func dir(_ a: Int, _ b: Int) -> (Double, Double) {
        let dx = px(b) - px(a), dy = py(b) - py(a)
        let l = (dx * dx + dy * dy).squareRoot()
        return l < 1e-9 ? (1.0, 0.0) : (dx / l, dy / l)
    }

    private func tangentForward(_ i: Int) -> (Double, Double) {
        var j = i, acc = 0.0, steps = 0
        while acc < 1.6 && steps < n / 2 {
            let dx = px(j + 1) - px(j), dy = py(j + 1) - py(j)
            acc += (dx * dx + dy * dy).squareRoot()
            j += 1; steps += 1
        }
        return dir(i, j)
    }

    private func tangentBackward(_ i: Int) -> (Double, Double) {
        var j = i, acc = 0.0, steps = 0
        while acc < 1.6 && steps < n / 2 {
            let dx = px(j - 1) - px(j), dy = py(j - 1) - py(j)
            acc += (dx * dx + dy * dy).squareRoot()
            j -= 1; steps += 1
        }
        return dir(i, j)
    }

    private func findCorners() -> [Bool] {
        var ang = [Double](repeating: 0, count: n)
        var lo = [Int](repeating: 0, count: n)
        var hi = [Int](repeating: 0, count: n)
        for i in 0..<n {
            var j = i, acc = 0.0, st = 0
            while acc < cornerWin && st < n / 2 {
                let dx = px(j) - px(j - 1), dy = py(j) - py(j - 1)
                acc += (dx * dx + dy * dy).squareRoot()
                j -= 1; st += 1
            }
            var k = i
            acc = 0.0; st = 0
            while acc < cornerWin && st < n / 2 {
                let dx = px(k + 1) - px(k), dy = py(k + 1) - py(k)
                acc += (dx * dx + dy * dy).squareRoot()
                k += 1; st += 1
            }
            lo[i] = j; hi[i] = k
            let v1x = px(i) - px(j), v1y = py(i) - py(j)
            let v2x = px(k) - px(i), v2y = py(k) - py(i)
            let l = (v1x * v1x + v1y * v1y).squareRoot() * (v2x * v2x + v2y * v2y).squareRoot()
            if l < 1e-9 {
                ang[i] = 0
            } else {
                let c = min(1.0, max(-1.0, (v1x * v2x + v1y * v2y) / l))
                ang[i] = acos(c) * 180.0 / Double.pi
            }
        }
        var res = [Bool](repeating: false, count: n)
        for i in 0..<n {
            if ang[i] < cornerDeg { continue }
            var best = true
            var t = lo[i]
            while t < i { if ang[((t % n) + n) % n] >= ang[i] { best = false; break }; t += 1 }
            if best {
                t = i + 1
                while t <= hi[i] { if ang[((t % n) + n) % n] > ang[i] { best = false; break }; t += 1 }
            }
            res[i] = best
        }
        return res
    }

    // ---- Schneider ----
    private func fitRun(_ first: Int, _ last: Int, _ t1x: Double, _ t1y: Double, _ t2x: Double, _ t2y: Double) {
        let cnt = last - first + 1
        if cnt < 2 { return }
        var xs = [Double](repeating: 0, count: cnt)
        var ys = [Double](repeating: 0, count: cnt)
        for i in 0..<cnt { xs[i] = px(first + i); ys[i] = py(first + i) }
        fitCubic(xs, ys, 0, cnt - 1, t1x, t1y, t2x, t2y)
    }

    private func emit(_ b: [Double]) {
        out.append(Float(b[2])); out.append(Float(b[3]))
        out.append(Float(b[4])); out.append(Float(b[5]))
        out.append(Float(b[6])); out.append(Float(b[7]))
    }

    private func fitCubic(_ xs: [Double], _ ys: [Double], _ first: Int, _ last: Int,
                          _ t1x: Double, _ t1y: Double, _ t2x: Double, _ t2y: Double) {
        let cnt = last - first + 1
        if cnt == 2 {
            let ddx = xs[last] - xs[first], ddy = ys[last] - ys[first]
            let d = (ddx * ddx + ddy * ddy).squareRoot() / 3.0
            emit([xs[first], ys[first], xs[first] + t1x * d, ys[first] + t1y * d,
                  xs[last] + t2x * d, ys[last] + t2y * d, xs[last], ys[last]])
            return
        }
        var u = chord(xs, ys, first, last)
        var bez = generate(xs, ys, first, last, u, t1x, t1y, t2x, t2y)
        var res = maxError(xs, ys, first, last, bez, u)
        if res.0 < err2 { emit(bez); return }
        if res.0 < err2 * 16 {
            for _ in 0..<4 {
                u = reparam(xs, ys, first, u, bez)
                bez = generate(xs, ys, first, last, u, t1x, t1y, t2x, t2y)
                res = maxError(xs, ys, first, last, bez, u)
                if res.0 < err2 { emit(bez); return }
            }
        }
        var sp = res.1
        if sp <= first { sp = first + 1 }
        if sp >= last { sp = last - 1 }
        let cx = xs[sp - 1] - xs[sp + 1], cy = ys[sp - 1] - ys[sp + 1]
        let l = (cx * cx + cy * cy).squareRoot()
        let tcx = l < 1e-9 ? 1.0 : cx / l
        let tcy = l < 1e-9 ? 0.0 : cy / l
        fitCubic(xs, ys, first, sp, t1x, t1y, tcx, tcy)
        fitCubic(xs, ys, sp, last, -tcx, -tcy, t2x, t2y)
    }

    private func chord(_ xs: [Double], _ ys: [Double], _ first: Int, _ last: Int) -> [Double] {
        var u = [Double](repeating: 0, count: last - first + 1)
        if last > first {
            for i in (first + 1)...last {
                let dx = xs[i] - xs[i - 1], dy = ys[i] - ys[i - 1]
                u[i - first] = u[i - first - 1] + (dx * dx + dy * dy).squareRoot()
            }
        }
        let tot = u[last - first]
        if tot < 1e-12 {
            for i in 0..<u.count { u[i] = Double(i) / Double(u.count - 1) }
        } else {
            for i in 0..<u.count { u[i] /= tot }
        }
        return u
    }

    private func generate(_ xs: [Double], _ ys: [Double], _ first: Int, _ last: Int, _ u: [Double],
                          _ t1x: Double, _ t1y: Double, _ t2x: Double, _ t2y: Double) -> [Double] {
        let p0x = xs[first], p0y = ys[first], p3x = xs[last], p3y = ys[last]
        var c00 = 0.0, c01 = 0.0, c11 = 0.0, x0 = 0.0, x1 = 0.0
        for i in 0...(last - first) {
            let t = u[i], s = 1 - t
            let b0 = s * s * s, b1 = 3 * s * s * t, b2 = 3 * s * t * t, b3 = t * t * t
            let a1x = t1x * b1, a1y = t1y * b1, a2x = t2x * b2, a2y = t2y * b2
            c00 += a1x * a1x + a1y * a1y
            c01 += a1x * a2x + a1y * a2y
            c11 += a2x * a2x + a2y * a2y
            let tx = xs[first + i] - (p0x * (b0 + b1) + p3x * (b2 + b3))
            let ty = ys[first + i] - (p0y * (b0 + b1) + p3y * (b2 + b3))
            x0 += a1x * tx + a1y * ty
            x1 += a2x * tx + a2y * ty
        }
        let det = c00 * c11 - c01 * c01
        var aL = 0.0, aR = 0.0
        if abs(det) > 1e-12 { aL = (x0 * c11 - x1 * c01) / det; aR = (c00 * x1 - c01 * x0) / det }
        let sx = p3x - p0x, sy = p3y - p0y
        let seg = (sx * sx + sy * sy).squareRoot()
        let eps = 1e-6 * seg
        if aL < eps || aR < eps || aL > seg * 2.5 || aR > seg * 2.5 { aL = seg / 3; aR = seg / 3 }
        return [p0x, p0y, p0x + t1x * aL, p0y + t1y * aL, p3x + t2x * aR, p3y + t2y * aR, p3x, p3y]
    }

    @inline(__always) private func bez(_ b: [Double], _ t: Double) -> (Double, Double) {
        let s = 1 - t
        let b0 = s * s * s, b1 = 3 * s * s * t, b2 = 3 * s * t * t, b3 = t * t * t
        return (b[0] * b0 + b[2] * b1 + b[4] * b2 + b[6] * b3,
                b[1] * b0 + b[3] * b1 + b[5] * b2 + b[7] * b3)
    }

    private func maxError(_ xs: [Double], _ ys: [Double], _ first: Int, _ last: Int,
                          _ b: [Double], _ u: [Double]) -> (Double, Int) {
        var worst = 0.0
        var split = (first + last) / 2
        if last - first >= 2 {
            for i in (first + 1)..<last {
                let p = bez(b, u[i - first])
                let dx = p.0 - xs[i], dy = p.1 - ys[i]
                let d = dx * dx + dy * dy
                if d >= worst { worst = d; split = i }
            }
        }
        return (worst, split)
    }

    private func reparam(_ xs: [Double], _ ys: [Double], _ first: Int, _ u: [Double], _ b: [Double]) -> [Double] {
        var r = [Double](repeating: 0, count: u.count)
        for i in 0..<u.count {
            let t = u[i]
            let p = bez(b, t)
            let s = 1 - t
            let d1x = 3 * (s * s * (b[2] - b[0]) + 2 * s * t * (b[4] - b[2]) + t * t * (b[6] - b[4]))
            let d1y = 3 * (s * s * (b[3] - b[1]) + 2 * s * t * (b[5] - b[3]) + t * t * (b[7] - b[5]))
            let d2x = 6 * (s * (b[4] - 2 * b[2] + b[0]) + t * (b[6] - 2 * b[4] + b[2]))
            let d2y = 6 * (s * (b[5] - 2 * b[3] + b[1]) + t * (b[7] - 2 * b[5] + b[3]))
            let dx = p.0 - xs[first + i], dy = p.1 - ys[first + i]
            let num = dx * d1x + dy * d1y
            let den = d1x * d1x + d1y * d1y + dx * d2x + dy * d2y
            if abs(den) < 1e-12 { r[i] = t } else { r[i] = min(1.0, max(0.0, t - num / den)) }
        }
        if r.count > 1 { for i in 1..<r.count where r[i] < r[i - 1] { r[i] = r[i - 1] } }
        return r
    }
}
