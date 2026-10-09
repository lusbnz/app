import SwiftUI

/// Xem ảnh toàn màn hình, chụm để phóng to.
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1

    let image: UIImage

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(zoom)
            .gesture(MagnifyGesture()
                .onChanged { zoom = max(1, $0.magnification) }
                .onEnded { _ in withAnimation { zoom = 1 } })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.4), in: .circle)
                }
                .padding()
                .accessibilityLabel("Đóng")
            }
            .accessibilityLabel("Ảnh hóa đơn")
    }
}

#Preview {
    PhotoViewer(image: UIImage(systemName: "doc.text") ?? UIImage())
}
