import UIKit

struct HistoryEntry: Identifiable {
    let id: Int64
    let mode: Mode
    let svgURL: URL
    let origURL: URL
}

/// Historial simple: cada conversión guarda el SVG y una copia chica de la imagen original.
enum History {
    private static let maxItems = 20

    private static func dir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("historial", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func add(_ v: VectorImage, _ mode: Mode, _ original: UIImage) throws {
        let id = Int64(Date().timeIntervalSince1970 * 1000)
        let base = "\(id)_\(mode.rawValue)"
        let d = dir()
        try Data(Svg.write(v).utf8).write(to: d.appendingPathComponent(base + ".svg"), options: .atomic)
        let small = ImageTools.normalized(original, maxSide: 1000)
        if let jpg = small.jpegData(compressionQuality: 0.88) {
            try jpg.write(to: d.appendingPathComponent(base + ".jpg"), options: .atomic)
        }
        for e in list().dropFirst(maxItems) { delete(e) }
    }

    static func list() -> [HistoryEntry] {
        let d = dir()
        let files = (try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? []
        var out: [HistoryEntry] = []
        for f in files where f.pathExtension == "svg" {
            let parts = f.deletingPathExtension().lastPathComponent.split(separator: "_")
            guard parts.count >= 2, let id = Int64(parts[0]) else { continue }
            let mode: Mode = parts[1] == "MAX" ? .maxQuality : .fast
            let orig = f.deletingPathExtension().appendingPathExtension("jpg")
            if FileManager.default.fileExists(atPath: orig.path) {
                out.append(HistoryEntry(id: id, mode: mode, svgURL: f, origURL: orig))
            }
        }
        return out.sorted(by: { $0.id > $1.id })
    }

    static func delete(_ e: HistoryEntry) {
        try? FileManager.default.removeItem(at: e.svgURL)
        try? FileManager.default.removeItem(at: e.origURL)
    }
}
