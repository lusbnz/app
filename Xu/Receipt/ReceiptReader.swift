import UIKit
import Vision

/// Nhận dạng chữ trên ảnh hóa đơn, chạy hoàn toàn trên máy.
enum ReceiptReader {
    /// Các dòng chữ, từ trên xuống dưới.
    static func lines(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [Locale.Language(identifier: "vi-VN"), Locale.Language(identifier: "en-US")]
        let observations = try await request.perform(on: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
        return rows(of: observations.compactMap { observation in
            observation.topCandidates(1).first.map {
                Fragment(text: $0.string, midY: observation.boundingBox.cgRect.midY,
                         minX: observation.boundingBox.cgRect.minX, height: observation.boundingBox.cgRect.height)
            }
        })
    }

    private struct Fragment {
        var text: String
        var midY: CGFloat
        var minX: CGFloat
        var height: CGFloat
    }

    /// Ghép các mảnh chữ nằm cùng hàng (nhãn bên trái, số tiền bên phải) thành một dòng.
    private static func rows(of fragments: [Fragment]) -> [String] {
        var rows: [[Fragment]] = []
        // Hệ tọa độ của Vision có gốc ở góc dưới trái, nên y lớn là phía trên.
        for fragment in fragments.sorted(by: { $0.midY > $1.midY }) {
            if let last = rows.last?.first, abs(last.midY - fragment.midY) < max(last.height, fragment.height) * 0.5 {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { $0.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ") }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
