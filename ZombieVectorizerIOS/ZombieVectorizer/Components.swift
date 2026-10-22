import SwiftUI
import UIKit

struct ZLabel: View {
    let text: String
    var primary = true
    var body: some View {
        Text(text)
            .font(.zombie(22))
            .foregroundColor(primary ? Pal.bg : Pal.green)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 18).fill(primary ? Pal.green : Pal.panel2))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Pal.green, lineWidth: primary ? 0 : 2))
    }
}

struct ZButton: View {
    let text: String
    var primary = true
    let action: () -> Void
    var body: some View {
        Button(action: action) { ZLabel(text: text, primary: primary) }
            .buttonStyle(.plain)
    }
}

struct HeaderView: View {
    var small = false
    var body: some View {
        VStack(spacing: 2) {
            Text("ZOMBIE VECTORIZER")
                .font(.title(small ? 30 : 44))
                .foregroundColor(Pal.green)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text("By P.V.M.")
                .font(.system(size: 11))
                .foregroundColor(Pal.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

struct WorkingOverlay: View {
    let text: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            HStack(spacing: 14) {
                ProgressView().tint(Pal.green)
                Text(text).foregroundColor(Pal.text)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 18).fill(Pal.bg))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Pal.green, lineWidth: 2))
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onImage) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(_ onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onImage(nil) }
    }
}

/// Muestra la imagen original y el vector, separados por un deslizador que se arrastra con el dedo.
struct CompareView: View {
    let before: UIImage
    let after: UIImage
    @State private var split: CGFloat = 0.5

    private func fit(_ size: CGSize) -> CGSize {
        let a = after.size.width / max(1, after.size.height)
        let w = min(size.width, size.height * a)
        return CGSize(width: w, height: w / a)
    }

    var body: some View {
        GeometryReader { geo in
            let f = fit(geo.size)
            ZStack {
                Rectangle().fill(Pal.panel2)
                Image(uiImage: before).resizable()
                Image(uiImage: after).resizable()
                    .mask(
                        HStack(spacing: 0) {
                            Color.clear.frame(width: f.width * split)
                            Color.black
                        }
                    )
                Rectangle().fill(Pal.green).frame(width: 3)
                    .position(x: f.width * split, y: f.height / 2)
                    .frame(width: f.width, height: f.height, alignment: .topLeading)
                Circle().fill(Pal.green).frame(width: 34, height: 34)
                    .overlay(Text("◄►").font(.system(size: 12, weight: .bold)).foregroundColor(Pal.bg))
                    .position(x: f.width * split, y: f.height / 2)
                    .frame(width: f.width, height: f.height, alignment: .topLeading)
                VStack {
                    HStack {
                        tag("ORIGINAL")
                        Spacer()
                        tag("VECTOR")
                    }
                    Spacer()
                }
                .padding(8)
            }
            .frame(width: f.width, height: f.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    split = min(1, max(0, g.location.x / max(1, f.width)))
                }
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func tag(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(Pal.text)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.65)))
    }
}
