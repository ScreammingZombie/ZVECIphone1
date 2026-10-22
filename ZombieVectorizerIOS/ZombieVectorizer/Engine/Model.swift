import Foundation

/// Capa de color: lista de contornos cerrados. Cada contorno es
/// [x0, y0, (c1x, c1y, c2x, c2y, x, y) * N] (todos los tramos son cúbicas).
final class Layer {
    let color: UInt32            // 0xAARRGGBB
    let contours: [[Float]]
    init(color: UInt32, contours: [[Float]]) { self.color = color; self.contours = contours }
}

/// Resultado de vectorizar: capas apiladas (la primera va al fondo), relleno even-odd.
final class VectorImage {
    let width: Int
    let height: Int
    let layers: [Layer]
    let transparent: Bool
    init(width: Int, height: Int, layers: [Layer], transparent: Bool) {
        self.width = width; self.height = height; self.layers = layers; self.transparent = transparent
    }
}

enum Mode: String {
    case fast = "FAST"
    case maxQuality = "MAX"
}

struct Analysis {
    let isPhoto: Bool
    let isSmall: Bool
    let score: Float
    var recommended: Mode { (isPhoto || isSmall) ? .maxQuality : .fast }
}

protocol ProgressSink: AnyObject {
    func update(_ stage: String, _ fraction: Float)
    func cancelled() -> Bool
}

struct CancelledError: Error {}
struct SvgError: Error {}
