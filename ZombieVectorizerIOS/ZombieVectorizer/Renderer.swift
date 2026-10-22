import UIKit

enum ImageTools {
    /// Aplica la orientación EXIF y reduce el lado más largo a `maxSide` (para cuidar la memoria).
    static func normalized(_ img: UIImage, maxSide: CGFloat) -> UIImage {
        let s = img.size
        let k = min(1, maxSide / max(s.width, s.height))
        let size = CGSize(width: max(1, (s.width * k).rounded()), height: max(1, (s.height * k).rounded()))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Píxeles ARGB (sin premultiplicar) de una imagen.
    static func pixels(_ img: UIImage) -> ([UInt32], Int, Int)? {
        guard let cg = img.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var raw = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = raw.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        if !ok { return nil }
        var out = [UInt32](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let a = UInt32(raw[i * 4 + 3])
            var r = UInt32(raw[i * 4]), g = UInt32(raw[i * 4 + 1]), b = UInt32(raw[i * 4 + 2])
            if a == 0 {
                out[i] = 0
                continue
            }
            if a < 255 {
                r = min(255, r * 255 / a); g = min(255, g * 255 / a); b = min(255, b * 255 / a)
            }
            out[i] = (a << 24) | (r << 16) | (g << 8) | b
        }
        return (out, w, h)
    }
}

enum Renderer {
    private static func draw(_ v: VectorImage, _ cg: CGContext) {
        for layer in v.layers {
            let path = CGMutablePath()
            for c in layer.contours {
                path.move(to: CGPoint(x: Double(c[0]), y: Double(c[1])))
                var i = 2
                while i + 5 < c.count {
                    path.addCurve(to: CGPoint(x: Double(c[i + 4]), y: Double(c[i + 5])),
                                  control1: CGPoint(x: Double(c[i]), y: Double(c[i + 1])),
                                  control2: CGPoint(x: Double(c[i + 2]), y: Double(c[i + 3])))
                    i += 6
                }
                path.closeSubpath()
            }
            let col = layer.color
            cg.setFillColor(red: CGFloat((col >> 16) & 0xFF) / 255, green: CGFloat((col >> 8) & 0xFF) / 255,
                            blue: CGFloat(col & 0xFF) / 255, alpha: 1)
            cg.addPath(path)
            cg.fillPath(using: .evenOdd)
        }
    }

    /// Dibuja el vector en una imagen cuyo lado más largo mide `longSide` píxeles.
    static func image(_ v: VectorImage, longSide: Int) -> UIImage {
        let k = CGFloat(longSide) / CGFloat(max(v.width, v.height))
        let size = CGSize(width: max(1, (CGFloat(v.width) * k).rounded()), height: max(1, (CGFloat(v.height) * k).rounded()))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = !v.transparent
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cg = ctx.cgContext
            cg.scaleBy(x: size.width / CGFloat(v.width), y: size.height / CGFloat(v.height))
            draw(v, cg)
        }
    }

    /// PDF con las formas como vectores reales (no una foto dentro del PDF).
    static func pdf(_ v: VectorImage) -> Data {
        let k = 842 / CGFloat(max(v.width, v.height))
        let pw = max(1, (CGFloat(v.width) * k).rounded()), ph = max(1, (CGFloat(v.height) * k).rounded())
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pw, height: ph))
        return renderer.pdfData { ctx in
            ctx.beginPage()
            let cg = ctx.cgContext
            cg.scaleBy(x: pw / CGFloat(v.width), y: ph / CGFloat(v.height))
            draw(v, cg)
        }
    }

    static func fitLongSide(_ v: VectorImage, wanted: Int, maxPixels: Double) -> Int {
        let k = Double(wanted) / Double(max(v.width, v.height))
        let px = (Double(v.width) * k) * (Double(v.height) * k)
        return px <= maxPixels ? wanted : Int(Double(wanted) * (maxPixels / px).squareRoot())
    }
}
