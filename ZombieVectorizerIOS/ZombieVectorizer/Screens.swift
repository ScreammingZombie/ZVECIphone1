import SwiftUI
import PhotosUI

struct RootView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        ZStack {
            Pal.bg.ignoresSafeArea()
            switch model.screen {
            case .splash: SplashView()
            case .home: HomeView()
            case .busy: BusyView()
            case .modes: ModesView()
            case .processing: ProcessingView()
            case .result: ResultView()
            case .history: HistoryView()
            }
            if let w = model.working { WorkingOverlay(text: w) }
            if let t = model.toast {
                VStack {
                    Spacer()
                    Text(t)
                        .font(.system(size: 14))
                        .foregroundColor(Pal.text)
                        .multilineTextAlignment(.center)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Pal.panel2))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Pal.green, lineWidth: 1))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                }
            }
        }
        .environmentObject(model)
        .sheet(item: $model.shareItem) { item in
            ShareSheet(url: item.url)
        }
    }
}

struct SplashView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Image("logo")
            .resizable()
            .scaledToFit()
            .ignoresSafeArea()
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if model.screen == .splash { model.screen = .home }
                }
            }
    }
}

struct BusyView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Pal.green).scaleEffect(1.6)
            Text(model.busyText).foregroundColor(Pal.text)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HeaderView()
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 220)
                    .padding(.vertical, 8)
                Text("Convertí cualquier imagen a vector. Todo funciona sin internet.")
                    .font(.system(size: 14))
                    .foregroundColor(Pal.text)
                    .multilineTextAlignment(.center)
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    ZLabel(text: "ELEGIR IMAGEN")
                }
                ZButton(text: "SACAR FOTO") {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCamera = true
                    } else {
                        model.showToast("Este dispositivo no tiene cámara disponible")
                    }
                }
                ZButton(text: "HISTORIAL", primary: false) { model.openHistory() }
            }
            .padding(18)
        }
        .onChange(of: pickerItem) { item in
            guard let item = item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.load(data: data)
                } else {
                    model.showToast("No se pudo abrir la imagen")
                }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                showCamera = false
                if let img = img { model.load(image: img) }
            }
            .ignoresSafeArea()
        }
    }
}

struct ModesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let a = model.analysis
        let rec = a?.recommended ?? .fast
        ScrollView {
            VStack(spacing: 12) {
                HeaderView(small: true)
                if let img = model.original {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Pal.panel))
                    Text("\(Int(img.size.width)) × \(Int(img.size.height)) px")
                        .font(.system(size: 12))
                        .foregroundColor(Pal.gray)
                }
                if a?.isPhoto == true {
                    Text("Las fotos pueden dar resultados artísticos y archivos pesados.")
                        .font(.system(size: 13))
                        .foregroundColor(Pal.warn)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Pal.panel))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Pal.warn, lineWidth: 1))
                }
                Text("¿Cómo querés convertirla?")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Pal.text)
                    .padding(.top, 6)
                ModeCard(title: "RÁPIDO",
                         desc: "Convierte al instante. Ideal para logos y dibujos nítidos.",
                         recommended: rec == .fast) { model.startConversion(.fast) }
                ModeCard(title: "MÁXIMA CALIDAD",
                         desc: "Mejora la imagen primero y después la convierte. Tarda más, pero rinde mejor con imágenes borrosas o chicas.",
                         recommended: rec == .maxQuality) { model.startConversion(.maxQuality) }
                ZButton(text: "VOLVER", primary: false) { model.goHome() }
            }
            .padding(18)
        }
    }
}

struct ModeCard: View {
    let title: String
    let desc: String
    let recommended: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.zombie(26)).foregroundColor(Pal.green)
                if recommended {
                    Text("★ RECOMENDADO")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Pal.warn)
                }
                Text(desc)
                    .font(.system(size: 14))
                    .foregroundColor(Pal.text)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18).fill(Pal.panel))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(recommended ? Pal.green : Pal.darkGreen, lineWidth: recommended ? 3 : 1))
        }
        .buttonStyle(.plain)
    }
}

struct ProcessingView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 14) {
            HeaderView(small: true)
            Text("Convirtiendo…")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Pal.green)
                .padding(.top, 30)
            Text(model.stage).font(.system(size: 15)).foregroundColor(Pal.text)
            ProgressView(value: model.progress)
                .tint(Pal.green)
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .padding(.vertical, 6)
            Text("\(Int(model.progress * 100))%").font(.system(size: 14)).foregroundColor(Pal.gray)
            Text("No cierres la app mientras convierte.")
                .font(.system(size: 12))
                .foregroundColor(Pal.gray)
                .padding(.top, 8)
            ZButton(text: "CANCELAR", primary: false) { model.cancelConversion() }
                .padding(.top, 14)
            Spacer()
        }
        .padding(18)
    }
}

enum ChooserKind: Identifiable {
    case save, share
    var id: Int { self == .save ? 0 : 1 }
}

struct ResultView: View {
    @EnvironmentObject var model: AppModel
    @State private var chooser: ChooserKind?

    private func modeName(_ m: Mode) -> String { m == .fast ? "Rápido" : "Máxima calidad" }

    var body: some View {
        VStack(spacing: 10) {
            HeaderView(small: true)
            if let after = model.resultPreview {
                CompareView(before: model.resultOrig ?? after, after: after)
            } else {
                Spacer()
            }
            Text("\(modeName(model.resultMode)) · \(model.result?.layers.count ?? 0) capas · deslizá para comparar")
                .font(.system(size: 12))
                .foregroundColor(Pal.gray)
            HStack(spacing: 10) {
                ZButton(text: "GUARDAR") { chooser = .save }
                ZButton(text: "COMPARTIR") { chooser = .share }
            }
            ZButton(text: "NUEVA IMAGEN", primary: false) { model.goHome() }
        }
        .padding(18)
        .sheet(item: $chooser) { kind in
            FormatSheet { f in
                chooser = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if kind == .save { model.save(f) } else { model.share(f) }
                }
            }
        }
    }
}

struct FormatSheet: View {
    let onPick: (Format) -> Void
    var body: some View {
        ZStack {
            Pal.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    Text("Elegí el formato")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Pal.green)
                        .padding(.top, 20)
                    ForEach(Format.allCases) { f in
                        Button { onPick(f) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.label).font(.zombie(22)).foregroundColor(Pal.green)
                                Text(f.desc).font(.system(size: 13)).foregroundColor(Pal.text)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Pal.panel))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Pal.darkGreen, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct HistoryView: View {
    @EnvironmentObject var model: AppModel

    private func modeName(_ m: Mode) -> String { m == .fast ? "Rápido" : "Máxima calidad" }

    private func dateText(_ id: Int64) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_AR")
        df.dateFormat = "dd/MM/yyyy HH:mm"
        return df.string(from: Date(timeIntervalSince1970: Double(id) / 1000))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HeaderView(small: true)
                Text("Historial")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Pal.green)
                    .padding(.top, 8)
                if model.history.isEmpty {
                    Text("Todavía no hay conversiones.")
                        .font(.system(size: 14))
                        .foregroundColor(Pal.gray)
                        .padding(.top, 20)
                }
                ForEach(model.history) { e in
                    Button { model.open(e) } label: {
                        HStack(spacing: 12) {
                            Image(uiImage: UIImage(contentsOfFile: e.origURL.path) ?? UIImage())
                                .resizable()
                                .scaledToFill()
                                .frame(width: 68, height: 68)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dateText(e.id)).font(.system(size: 15, weight: .bold)).foregroundColor(Pal.text)
                                Text(modeName(e.mode)).font(.system(size: 13)).foregroundColor(Pal.gray)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Pal.panel))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Pal.darkGreen, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { model.delete(e) } label: { Text("Borrar") }
                    }
                }
                if !model.history.isEmpty {
                    Text("Mantené apretado un elemento para borrarlo.")
                        .font(.system(size: 11))
                        .foregroundColor(Pal.gray)
                }
                ZButton(text: "VOLVER", primary: false) { model.goHome() }
                    .padding(.top, 10)
            }
            .padding(18)
        }
    }
}
