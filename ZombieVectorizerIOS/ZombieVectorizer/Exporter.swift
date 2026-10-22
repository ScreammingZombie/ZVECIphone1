import UIKit

enum Format: CaseIterable, Identifiable {
    case svg, pdf, png, pngHD

    var id: String { label }
    var label: String {
        switch self {
        case .svg: return "SVG"
        case .pdf: return "PDF"
        case .png: return "PNG normal"
        case .pngHD: return "PNG alta resolución"
        }
    }
    var desc: String {
        switch self {
        case .svg: return "Editable. Se agranda sin perder calidad."
        case .pdf: return "Listo para imprimir/enviar."
        case .png: return "Liviana, para compartir."
        case .pngHD: return "Enorme y nítido, para imprimir."
        }
    }
    var ext: String {
        switch self {
        case .svg: return "svg"
        case .pdf: return "pdf"
        case .png, .pngHD: return "png"
        }
    }
    var suffix: String { self == .pngHD ? "_hd" : "" }
}

struct ExportError: Error {}

enum Exporter {
    static func data(_ v: VectorImage, _ f: Format) throws -> Data {
        switch f {
        case .svg:
            return Data(Svg.write(v).utf8)
        case .pdf:
            return Renderer.pdf(v)
        case .png:
            let img = Renderer.image(v, longSide: Renderer.fitLongSide(v, wanted: 1600, maxPixels: 4_000_000))
            guard let d = img.pngData() else { throw ExportError() }
            return d
        case .pngHD:
            let img = Renderer.image(v, longSide: Renderer.fitLongSide(v, wanted: 4096, maxPixels: 16_000_000))
            guard let d = img.pngData() else { throw ExportError() }
            return d
        }
    }

    static func fileName(_ f: Format) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyMMdd_HHmmss"
        return "zombie_vector_\(df.string(from: Date()))\(f.suffix).\(f.ext)"
    }

    /// Guarda en la carpeta de la app (se ve en Archivos > En mi iPhone > Zombie Vectorizer).
    static func saveToDocuments(_ v: VectorImage, _ f: Format) throws -> String {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = fileName(f)
        try data(v, f).write(to: dir.appendingPathComponent(name), options: .atomic)
        return name
    }

    /// Arma el archivo en una carpeta temporal para el menú de compartir.
    static func shareURL(_ v: VectorImage, _ f: Format) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("compartir", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName(f))
        try data(v, f).write(to: url, options: .atomic)
        return url
    }
}
