import Foundation

/// Motor de vectorización 100% offline (Swift puro).
///  - RÁPIDO: cuantización de color + trazado + curvas Bézier.
///  - MÁXIMA CALIDAD: agranda (bicúbico), limpia ruido/artefactos JPEG (filtro bilateral),
///    usa más colores y ajusta las curvas con más precisión.
enum Vectorizer {
    static let photoScore: Float = 4.8

    // ------------------------------------------------------------ análisis
    static func analyze(_ px: [UInt32], _ w: Int, _ h: Int) -> Analysis {
        let small = max(w, h) < 700
        let hist = Histogram(px)
        if hist.opaque == 0 { return Analysis(isPhoto: false, isSmall: small, score: 0) }
        let pal = Palette.build(hist, kmax: 12, mergeDist: 5, fringe: 0)
        return Analysis(isPhoto: pal.meanError > photoScore, isSmall: small, score: pal.meanError)
    }

    // ------------------------------------------------------------ pipeline
    static func run(_ src: [UInt32], _ sw: Int, _ sh: Int, mode: Mode, progress p: ProgressSink) throws -> VectorImage {
        let hq = (mode == .maxQuality)
        let long = Float(max(sw, sh))
        var scale: Float = 1
        if hq {
            if long < 1600 { scale = min(3, 1600 / long) } else if long > 2400 { scale = 2400 / long }
        } else if long > 2000 {
            scale = 2000 / long
        }
        p.update("Preparando imagen", 0.02)
        var w = sw, h = sh
        var px = src
        if abs(scale - 1) > 0.01 {
            w = max(1, Int((Float(sw) * scale).rounded()))
            h = max(1, Int((Float(sh) * scale).rounded()))
            px = Resample.run(src, sw, sh, w, h)
        }
        if p.cancelled() { throw CancelledError() }
        if hq {
            p.update("Limpiando ruido", 0.08)
            px = try Bilateral.run(px, w, h, cancelled: { p.cancelled() })
        }

        p.update("Analizando colores", 0.15)
        let hist = Histogram(px)
        let total = hist.opaque
        let transparent = total < w * h
        if total == 0 { return VectorImage(width: w, height: h, layers: [], transparent: true) }
        let pal = Palette.buildAuto(hist, kmax: hq ? 48 : 24, mergeDist: hq ? 4.2 : 7,
                                    target: hq ? 2.2 : 3.5, fringe: hq ? 0.02 : 0.03)
        let n = pal.size

        // mapa de etiquetas ordenadas por área (0 = la más grande); 255 = transparente
        var labels = [UInt8](repeating: 255, count: w * h)
        for i in 0..<(w * h) {
            let c = px[i]
            if (c >> 24) >= 128 { labels[i] = pal.binLabel[Histogram.bin(c)] }
        }
        var bx0 = [Int](repeating: Int.max, count: n), by0 = [Int](repeating: Int.max, count: n)
        var bx1 = [Int](repeating: -1, count: n), by1 = [Int](repeating: -1, count: n)
        for y in 0..<h {
            for x in 0..<w {
                let l = Int(labels[y * w + x])
                if l < n {
                    if x < bx0[l] { bx0[l] = x }
                    if x > bx1[l] { bx1[l] = x }
                    if y < by0[l] { by0[l] = y }
                    if y > by1[l] { by1[l] = y }
                }
            }
        }

        let sc = max(1, scale)
        let lowRes = max(w, h) < 900   // imágenes chicas: más suavizado para disimular los escalones de píxeles
        let passes = hq ? (scale > 1.5 ? 2 : 1) : (lowRes ? 3 : 1)
        let tol: Double = hq ? 0.5 * (1 + Double(sc - 1) * 0.4) : (lowRes ? 0.35 : 0.5)
        let win: Double = 2.0 * (hq ? max(1.0, Double(sc) * 0.8) : 1.0)
        let minArea = 3.0 * Double(sc) * Double(sc)
        let cornerDeg: Double = hq ? 45.0 : 50.0

        let margin = 3
        let bufSize = (w + 2 * margin + 2) * (h + 2 * margin + 2)
        var bufA = [Float](repeating: 0, count: bufSize)
        var bufB = [Float](repeating: 0, count: bufSize)

        var layers: [Layer] = []
        for j in 0..<n {
            if p.cancelled() { throw CancelledError() }
            p.update("Trazando capa \(j + 1) de \(n)", 0.2 + 0.78 * Float(j) / Float(n))
            let color = pal.colors[j]
            if j == 0 && !transparent {
                let fw = Float(w), fh = Float(h)
                let rect: [Float] = [0, 0,
                                     0, 0, fw, 0, fw, 0,
                                     fw, 0, fw, fh, fw, fh,
                                     fw, fh, 0, fh, 0, fh,
                                     0, fh, 0, 0, 0, 0]
                layers.append(Layer(color: color, contours: [rect]))
                continue
            }
            var x0 = Int.max, y0 = Int.max, x1 = -1, y1 = -1
            for l in j..<n {
                if bx1[l] < 0 { continue }
                x0 = min(x0, bx0[l]); y0 = min(y0, by0[l]); x1 = max(x1, bx1[l]); y1 = max(y1, by1[l])
            }
            if x1 < 0 { continue }
            let contours = try Tracer.trace(labels: labels, w: w, h: h, j: j, x0: x0, y0: y0, x1: x1, y1: y1,
                                            A: &bufA, B: &bufB, passes: passes, err2: tol * tol, win: win,
                                            cornerDeg: cornerDeg, minArea: minArea, cancelled: { p.cancelled() })
            if !contours.isEmpty { layers.append(Layer(color: color, contours: contours)) }
        }
        p.update("Listo", 1)
        return VectorImage(width: w, height: h, layers: layers, transparent: transparent)
    }
}

// ================================================================ histograma + paleta
struct Histogram {
    var count = [Int](repeating: 0, count: 32768)
    var sr = [Int](repeating: 0, count: 32768)
    var sg = [Int](repeating: 0, count: 32768)
    var sb = [Int](repeating: 0, count: 32768)
    var opaque = 0

    @inline(__always) static func bin(_ c: UInt32) -> Int {
        return Int((((c >> 19) & 31) << 10) | (((c >> 11) & 31) << 5) | ((c >> 3) & 31))
    }

    init(_ px: [UInt32]) {
        for c in px {
            if (c >> 24) < 128 { continue }
            let b = Histogram.bin(c)
            count[b] += 1
            sr[b] += Int((c >> 16) & 0xFF); sg[b] += Int((c >> 8) & 0xFF); sb[b] += Int(c & 0xFF)
            opaque += 1
        }
    }
}

/// Generador pseudoaleatorio determinista (SplitMix64).
struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func nextDouble() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

struct Palette {
    let size: Int
    let colors: [UInt32]
    let binLabel: [UInt8]
    let meanError: Float

    private static let lin: [Float] = (0..<256).map { i -> Float in
        let c = Float(i) / 255
        return c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }

    static func distToSegment(_ px: Float, _ py: Float, _ pz: Float,
                              _ ax: Float, _ ay: Float, _ az: Float,
                              _ bx: Float, _ by: Float, _ bz: Float) -> Float {
        let dx = bx - ax, dy = by - ay, dz = bz - az
        let l2 = dx * dx + dy * dy + dz * dz
        var t: Float = l2 < 1e-9 ? 0 : ((px - ax) * dx + (py - ay) * dy + (pz - az) * dz) / l2
        t = min(1, max(0, t))
        let ex = ax + t * dx - px, ey = ay + t * dy - py, ez = az + t * dz - pz
        return (ex * ex + ey * ey + ez * ez).squareRoot()
    }

    static func lab(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let ri = min(255, max(0, Int(r.rounded()))), gi = min(255, max(0, Int(g.rounded()))), bi = min(255, max(0, Int(b.rounded())))
        let rl = lin[ri], gl = lin[gi], bl = lin[bi]
        let x = (0.4124 * rl + 0.3576 * gl + 0.1805 * bl) / 0.95047
        let y = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl
        let z = (0.0193 * rl + 0.1192 * gl + 0.9505 * bl) / 1.08883
        func f(_ t: Float) -> Float { t > 0.008856 ? cbrtf(t) : 7.787 * t + 16.0 / 116.0 }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// Prueba cantidades crecientes de colores y se queda con la primera que representa bien la imagen.
    static func buildAuto(_ h: Histogram, kmax: Int, mergeDist: Float, target: Float, fringe: Float) -> Palette {
        var best: Palette? = nil
        for k in [3, 5, 8, 12, 18, 24, 32, 40, 48] {
            if k > kmax && best != nil { break }
            let cand = build(h, kmax: min(k, kmax), mergeDist: mergeDist, fringe: fringe)
            best = cand
            if cand.meanError <= target { break }
        }
        return best!
    }

    static func build(_ h: Histogram, kmax: Int, mergeDist: Float, fringe: Float) -> Palette {
        // bins presentes
        var ids: [Int] = []
        var L: [Float] = [], A: [Float] = [], B: [Float] = [], wt: [Float] = []
        var mr: [Float] = [], mg: [Float] = [], mb: [Float] = []
        for i in 0..<32768 {
            let c = h.count[i]
            if c == 0 { continue }
            ids.append(i)
            let r = Float(h.sr[i]) / Float(c), g = Float(h.sg[i]) / Float(c), b = Float(h.sb[i]) / Float(c)
            mr.append(r); mg.append(g); mb.append(b)
            let l = lab(r, g, b)
            L.append(l.0); A.append(l.1); B.append(l.2); wt.append(Float(c))
        }
        let m = ids.count
        let kk = min(kmax, m)
        var cL = [Float](repeating: 0, count: kk), cA = [Float](repeating: 0, count: kk), cB = [Float](repeating: 0, count: kk)

        // k-means++ ponderado
        var rng = SplitMix64(state: 7)
        var first = 0
        for i in 0..<m where wt[i] > wt[first] { first = i }
        cL[0] = L[first]; cA[0] = A[first]; cB[0] = B[first]
        var minD = [Float](repeating: Float.greatestFiniteMagnitude, count: m)
        var cnt = 1
        while cnt < kk {
            var sum = 0.0
            for i in 0..<m {
                let dl = L[i] - cL[cnt - 1], da = A[i] - cA[cnt - 1], db = B[i] - cB[cnt - 1]
                let d = dl * dl + da * da + db * db
                if d < minD[i] { minD[i] = d }
                sum += Double(minD[i]) * Double(wt[i])
            }
            if sum < 1e-6 { break }
            var r = rng.nextDouble() * sum
            var pick = m - 1
            for i in 0..<m {
                r -= Double(minD[i]) * Double(wt[i])
                if r <= 0 { pick = i; break }
            }
            cL[cnt] = L[pick]; cA[cnt] = A[pick]; cB[cnt] = B[pick]
            cnt += 1
        }
        let kc = cnt
        var sL = [Double](repeating: 0, count: kc), sA = [Double](repeating: 0, count: kc)
        var sB = [Double](repeating: 0, count: kc), sW = [Double](repeating: 0, count: kc)
        for _ in 0..<12 {
            for c in 0..<kc { sL[c] = 0; sA[c] = 0; sB[c] = 0; sW[c] = 0 }
            for i in 0..<m {
                var best = 0
                var bd = Float.greatestFiniteMagnitude
                for c in 0..<kc {
                    let dl = L[i] - cL[c], da = A[i] - cA[c], db = B[i] - cB[c]
                    let d = dl * dl + da * da + db * db
                    if d < bd { bd = d; best = c }
                }
                let w = Double(wt[i])
                sL[best] += Double(L[i]) * w; sA[best] += Double(A[i]) * w; sB[best] += Double(B[i]) * w; sW[best] += w
            }
            for c in 0..<kc where sW[c] > 0 {
                cL[c] = Float(sL[c] / sW[c]); cA[c] = Float(sA[c] / sW[c]); cB[c] = Float(sB[c] / sW[c])
            }
        }
        // fusionar centros casi iguales
        var alive = [Bool](repeating: true, count: kc)
        var cw = sW
        var merged = true
        while merged {
            merged = false
            var bi = -1, bj = -1
            var bd = mergeDist * mergeDist
            for a in 0..<kc where alive[a] {
                for b in (a + 1)..<max(kc, a + 1) where alive[b] {
                    let dl = cL[a] - cL[b], da = cA[a] - cA[b], db = cB[a] - cB[b]
                    let d = dl * dl + da * da + db * db
                    if d < bd { bd = d; bi = a; bj = b }
                }
            }
            if bi >= 0 {
                let wa = cw[bi], wb = cw[bj], ws = max(1e-9, wa + wb)
                cL[bi] = Float((Double(cL[bi]) * wa + Double(cL[bj]) * wb) / ws)
                cA[bi] = Float((Double(cA[bi]) * wa + Double(cA[bj]) * wb) / ws)
                cB[bi] = Float((Double(cB[bi]) * wa + Double(cB[bj]) * wb) / ws)
                cw[bi] = ws; alive[bj] = false; merged = true
            }
        }
        var keepL: [Int] = (0..<kc).filter { alive[$0] && cw[$0] >= Double(h.opaque) * 0.0003 }
        if keepL.isEmpty {
            var bestC = 0
            for c in 0..<kc where cw[c] > cw[bestC] { bestC = c }
            keepL = [bestC]
        }
        // quitar colores "de transición" (bordes suavizados): chicos y ubicados entre otros dos colores
        if fringe > 0 {
            var changed = true
            while changed && keepL.count > 2 {
                changed = false
                for c in keepL.sorted(by: { cw[$0] < cw[$1] }) {
                    if cw[c] > Double(h.opaque) * Double(fringe) { break }
                    var between = false
                    outer: for a in keepL {
                        if a == c || cw[a] <= cw[c] { continue }
                        for b in keepL {
                            if b <= a || b == c || cw[b] <= cw[c] { continue }
                            if distToSegment(cL[c], cA[c], cB[c], cL[a], cA[a], cB[a], cL[b], cA[b], cB[b]) < 3.5 {
                                between = true
                                break outer
                            }
                        }
                    }
                    if between {
                        keepL.removeAll(where: { $0 == c })
                        changed = true
                        break
                    }
                }
            }
        }
        // asignación final y colores medios
        let ks = keepL.count
        var area = [Double](repeating: 0, count: ks)
        var ar = [Double](repeating: 0, count: ks), ag = [Double](repeating: 0, count: ks), ab = [Double](repeating: 0, count: ks)
        var finalAssign = [Int](repeating: 0, count: m)
        var errSum = 0.0
        for i in 0..<m {
            var best = 0
            var bd = Float.greatestFiniteMagnitude
            for t in 0..<ks {
                let c = keepL[t]
                let dl = L[i] - cL[c], da = A[i] - cA[c], db = B[i] - cB[c]
                let d = dl * dl + da * da + db * db
                if d < bd { bd = d; best = t }
            }
            finalAssign[i] = best
            let w = Double(wt[i])
            area[best] += w
            ar[best] += Double(mr[i]) * w; ag[best] += Double(mg[i]) * w; ab[best] += Double(mb[i]) * w
            errSum += Double(bd).squareRoot() * w
        }
        let order = (0..<ks).sorted(by: { area[$0] > area[$1] })
        var rank = [Int](repeating: 0, count: ks)
        for (r, t) in order.enumerated() { rank[t] = r }
        var colors = [UInt32](repeating: 0, count: ks)
        for t in 0..<ks {
            let a = max(1.0, area[t])
            let r = min(255, max(0, Int((ar[t] / a).rounded())))
            let g = min(255, max(0, Int((ag[t] / a).rounded())))
            let b = min(255, max(0, Int((ab[t] / a).rounded())))
            colors[rank[t]] = 0xFF00_0000 | (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
        }
        var binLabel = [UInt8](repeating: 0, count: 32768)
        for i in 0..<m { binLabel[ids[i]] = UInt8(rank[finalAssign[i]]) }
        return Palette(size: ks, colors: colors, binLabel: binLabel,
                       meanError: Float(errSum / Double(max(1, h.opaque))))
    }
}

// ================================================================ remuestreo bicúbico (Catmull-Rom)
enum Resample {
    private static func cr(_ x: Float) -> Float {
        let a = abs(x)
        if a < 1 { return 1.5 * a * a * a - 2.5 * a * a + 1 }
        if a < 2 { return -0.5 * a * a * a + 2.5 * a * a - 4 * a + 2 }
        return 0
    }

    private struct Axis {
        var first: [Int]
        var offset: [Int]
        var count: [Int]
        var weights: [Float]
    }

    private static func axis(_ n: Int, _ nn: Int) -> Axis {
        let scale = Float(nn) / Float(n)
        let fs = max(1, 1 / scale)
        let sup = 2 * fs
        var ax = Axis(first: [Int](repeating: 0, count: nn), offset: [Int](repeating: 0, count: nn),
                      count: [Int](repeating: 0, count: nn), weights: [])
        for i in 0..<nn {
            let c = (Float(i) + 0.5) / scale - 0.5
            let lo = Int((c - sup).rounded(.up)), hi = Int((c + sup).rounded(.down))
            var s: Float = 0
            let start = ax.weights.count
            for j in lo...hi {
                let v = cr((Float(j) - c) / fs)
                ax.weights.append(v); s += v
            }
            for k in start..<ax.weights.count { ax.weights[k] /= s }
            ax.first[i] = lo; ax.offset[i] = start; ax.count[i] = hi - lo + 1
        }
        return ax
    }

    static func run(_ src: [UInt32], _ w: Int, _ h: Int, _ nw: Int, _ nh: Int) -> [UInt32] {
        let ax = axis(w, nw), ay = axis(h, nh)
        var tr = [Float](repeating: 0, count: h * nw), tg = tr, tb = tr, ta = tr
        for y in 0..<h {
            let row = y * w
            for x in 0..<nw {
                var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                let f = ax.first[x], off = ax.offset[x]
                for k in 0..<ax.count[x] {
                    let sx = min(w - 1, max(0, f + k))
                    let c = src[row + sx]
                    let al = Float(c >> 24) / 255
                    let wk = ax.weights[off + k]
                    r += Float((c >> 16) & 0xFF) * al * wk
                    g += Float((c >> 8) & 0xFF) * al * wk
                    b += Float(c & 0xFF) * al * wk
                    a += al * wk
                }
                let o = y * nw + x
                tr[o] = r; tg[o] = g; tb[o] = b; ta[o] = a
            }
        }
        var out = [UInt32](repeating: 0, count: nw * nh)
        for y in 0..<nh {
            let f = ay.first[y], off = ay.offset[y]
            for x in 0..<nw {
                var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                for k in 0..<ay.count[y] {
                    let sy = min(h - 1, max(0, f + k))
                    let o = sy * nw + x
                    let wk = ay.weights[off + k]
                    r += tr[o] * wk; g += tg[o] * wk; b += tb[o] * wk; a += ta[o] * wk
                }
                let al = min(1, max(0, a))
                if al < 0.002 { out[y * nw + x] = 0; continue }
                let ri = UInt32(min(255, max(0, Int((r / a).rounded()))))
                let gi = UInt32(min(255, max(0, Int((g / a).rounded()))))
                let bi = UInt32(min(255, max(0, Int((b / a).rounded()))))
                let ai = UInt32((al * 255).rounded())
                out[y * nw + x] = (ai << 24) | (ri << 16) | (gi << 8) | bi
            }
        }
        return out
    }
}

// ================================================================ filtro bilateral (limpia ruido y artefactos JPEG)
enum Bilateral {
    static func run(_ src: [UInt32], _ w: Int, _ h: Int, cancelled: () -> Bool) throws -> [UInt32] {
        let rad = 2
        var sp = [Float](repeating: 0, count: 25)
        for dy in -rad...rad {
            for dx in -rad...rad {
                sp[(dy + rad) * 5 + dx + rad] = expf(-Float(dx * dx + dy * dy) / (2 * 1.3 * 1.3))
            }
        }
        var rng = [Float](repeating: 0, count: 766)
        for i in 0..<766 {
            let d = Float(i) / 3
            rng[i] = expf(-(d * d) / (2 * 26 * 26))
        }
        var out = [UInt32](repeating: 0, count: src.count)
        for y in 0..<h {
            if (y & 63) == 0 && cancelled() { throw CancelledError() }
            for x in 0..<w {
                let c = src[y * w + x]
                let cr = Int((c >> 16) & 0xFF), cg = Int((c >> 8) & 0xFF), cb = Int(c & 0xFF)
                var sr: Float = 0, sg: Float = 0, sb: Float = 0, sw: Float = 0
                for dy in -rad...rad {
                    let yy = min(h - 1, max(0, y + dy))
                    for dx in -rad...rad {
                        let xx = min(w - 1, max(0, x + dx))
                        let q = src[yy * w + xx]
                        let qr = Int((q >> 16) & 0xFF), qg = Int((q >> 8) & 0xFF), qb = Int(q & 0xFF)
                        let wgt = sp[(dy + rad) * 5 + dx + rad] * rng[abs(qr - cr) + abs(qg - cg) + abs(qb - cb)]
                        sr += Float(qr) * wgt; sg += Float(qg) * wgt; sb += Float(qb) * wgt; sw += wgt
                    }
                }
                let r = UInt32((sr / sw).rounded()), g = UInt32((sg / sw).rounded()), b = UInt32((sb / sw).rounded())
                out[y * w + x] = (c & 0xFF00_0000) | (r << 16) | (g << 8) | b
            }
        }
        return out
    }
}
