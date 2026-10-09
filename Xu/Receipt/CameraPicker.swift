import SwiftUI
import UIKit

/// Camera của hệ thống. Chỉ mở khi máy có camera và Info đã khai báo quyền.
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (UIImage) -> Void

    /// Thiếu khóa NSCameraUsageDescription thì mở camera sẽ làm app bị hệ thống đóng.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
            && Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage) { dismiss() }
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onImage: (UIImage) -> Void
        private let close: () -> Void

        init(onImage: @escaping (UIImage) -> Void, close: @escaping () -> Void) {
            self.onImage = onImage
            self.close = close
        }

        func imagePickerController(
            _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage { onImage(image) }
            close()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            close()
        }
    }
}
