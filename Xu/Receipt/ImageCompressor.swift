import UIKit

enum ImageCompressor {
    /// Thu ảnh về cạnh dài tối đa `maxSide` điểm ảnh rồi nén JPEG.
    static func jpeg(from image: UIImage, maxSide: CGFloat = 1_600, quality: CGFloat = 0.6) -> Data? {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longest = max(pixels.width, pixels.height)
        guard longest > 0 else { return nil }
        let ratio = min(1, maxSide / longest)
        let target = CGSize(width: (pixels.width * ratio).rounded(), height: (pixels.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    static func jpeg(from data: Data) -> Data? {
        UIImage(data: data).flatMap { jpeg(from: $0) }
    }
}
