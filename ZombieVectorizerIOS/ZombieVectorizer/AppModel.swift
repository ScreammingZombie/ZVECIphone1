import SwiftUI

enum Screen { case splash, home, busy, modes, processing, result, history }

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

final class CancelFlag {
    private let lock = NSLock()
    private var flag = false
    func reset() { lock.lock(); flag = false; lock.unlock() }
    func set() { lock.lock(); flag = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

/// Recibe el progreso del motor (que corre en otro hilo) y lo pasa al hilo principal.
final class ProgressRelay: ProgressSink {
    private weak var model: AppModel?
    private let cancel: CancelFlag
    init(model: AppModel, cancel: CancelFlag) { self.model = model; self.cancel = cancel }
    func update(_ stage: String, _ fraction: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.model?.stage = stage
            self?.model?.progress = Double(fraction)
        }
    }
    func cancelled() -> Bool { cancel.isSet }
}

final class AppModel: ObservableObject {
    @Published var screen: Screen = .splash
    @Published var busyText = ""
    @Published var original: UIImage?
    @Published var analysis: Analysis?
    @Published var stage = ""
    @Published var progress: Double = 0
    @Published var result: VectorImage?
    @Published var resultMode: Mode = .fast
    @Published var resultOrig: UIImage?
    @Published var resultPreview: UIImage?
    @Published var toast: String?
    @Published var working: String?
    @Published var history: [HistoryEntry] = []
    @Published var shareItem: ShareItem?

    private var pixels: [UInt32] = []
    private var pw = 0
    private var ph = 0
    private let cancel = CancelFlag()

    func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    func showToast(_ s: String) {
        toast = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.toast == s { self?.toast = nil }
        }
    }

    func goHome() {
        UIApplication.shared.isIdleTimerDisabled = false
        screen = .home
    }

    // ------------------------------------------------------------ cargar imagen
    func load(data: Data) {
        guard let img = UIImage(data: data) else {
            showToast("No se pudo abrir la imagen")
            return
        }
        load(image: img)
    }

    func load(image: UIImage) {
        busyText = "Cargando imagen…"
        screen = .busy
        let t = Thread { [weak self] in
            guard let self = self else { return }
            let norm = ImageTools.normalized(image, maxSide: 3000)
            guard let px = ImageTools.pixels(norm) else {
                self.onMain { self.showToast("No se pudo abrir la imagen"); self.screen = .home }
                return
            }
            let a = Vectorizer.analyze(px.0, px.1, px.2)
            self.onMain {
                self.original = norm
                self.pixels = px.0
                self.pw = px.1
                self.ph = px.2
                self.analysis = a
                self.screen = .modes
            }
        }
        t.stackSize = 16 << 20
        t.start()
    }

    // ------------------------------------------------------------ convertir
    func startConversion(_ mode: Mode) {
        cancel.reset()
        stage = "Empezando"
        progress = 0
        screen = .processing
        UIApplication.shared.isIdleTimerDisabled = true
        let src = pixels, w = pw, h = ph
        let orig = original
        let relay = ProgressRelay(model: self, cancel: cancel)
        let t = Thread { [weak self] in
            guard let self = self else { return }
            do {
                let v = try Vectorizer.run(src, w, h, mode: mode, progress: relay)
                self.onMain { self.stage = "Preparando vista previa" }
                let preview = Renderer.image(v, longSide: 1600)
                if let o = orig { try? History.add(v, mode, o) }
                self.onMain {
                    self.result = v
                    self.resultMode = mode
                    self.resultOrig = orig
                    self.resultPreview = preview
                    UIApplication.shared.isIdleTimerDisabled = false
                    self.screen = .result
                }
            } catch is CancelledError {
                self.onMain { UIApplication.shared.isIdleTimerDisabled = false; self.screen = .modes }
            } catch {
                self.onMain {
                    UIApplication.shared.isIdleTimerDisabled = false
                    self.showToast("No se pudo convertir la imagen")
                    self.screen = .modes
                }
            }
        }
        t.stackSize = 16 << 20
        t.qualityOfService = .userInitiated
        t.start()
    }

    func cancelConversion() { cancel.set() }

    // ------------------------------------------------------------ guardar y compartir
    func save(_ f: Format) {
        guard let v = result else { return }
        working = "Guardando \(f.label)…"
        let t = Thread { [weak self] in
            guard let self = self else { return }
            do {
                let name = try Exporter.saveToDocuments(v, f)
                self.onMain {
                    self.working = nil
                    self.showToast("Guardado en Archivos > Zombie Vectorizer > \(name)")
                }
            } catch {
                self.onMain { self.working = nil; self.showToast("No se pudo guardar") }
            }
        }
        t.stackSize = 16 << 20
        t.start()
    }

    func share(_ f: Format) {
        guard let v = result else { return }
        working = "Preparando \(f.label)…"
        let t = Thread { [weak self] in
            guard let self = self else { return }
            do {
                let url = try Exporter.shareURL(v, f)
                self.onMain { self.working = nil; self.shareItem = ShareItem(url: url) }
            } catch {
                self.onMain { self.working = nil; self.showToast("No se pudo compartir") }
            }
        }
        t.stackSize = 16 << 20
        t.start()
    }

    // ------------------------------------------------------------ historial
    func openHistory() {
        history = History.list()
        screen = .history
    }

    func delete(_ e: HistoryEntry) {
        History.delete(e)
        history = History.list()
    }

    func open(_ e: HistoryEntry) {
        busyText = "Abriendo…"
        screen = .busy
        let t = Thread { [weak self] in
            guard let self = self else { return }
            do {
                let v = try Svg.parse(try Data(contentsOf: e.svgURL))
                let orig = UIImage(contentsOfFile: e.origURL.path)
                let preview = Renderer.image(v, longSide: 1600)
                self.onMain {
                    self.result = v
                    self.resultMode = e.mode
                    self.resultOrig = orig
                    self.resultPreview = preview
                    self.screen = .result
                }
            } catch {
                self.onMain { self.showToast("No se pudo abrir esta conversión"); self.openHistory() }
            }
        }
        t.stackSize = 16 << 20
        t.start()
    }
}
