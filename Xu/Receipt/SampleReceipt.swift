#if DEBUG
import UIKit

/// Hóa đơn mẫu vẽ bằng chữ, cho #Preview và để thử bộ đọc trên máy ảo (máy ảo không có camera).
enum SampleReceipt {
    static func image(now: Date = Date(), calendar: Calendar = .current) -> UIImage {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let parts = calendar.dateComponents([.day, .month, .year], from: yesterday)
        let day = String(format: "%02d/%02d/%04d", parts.day ?? 1, parts.month ?? 1, parts.year ?? 2026)
        let rows: [(String, String)] = [
            ("QUÁN CƠM TẤM BA GHIỀN", ""),
            ("84 Đặng Văn Ngữ, Phú Nhuận", ""),
            ("Ngày: \(day) 19:42", ""),
            ("Cơm sườn bì chả x2", "150.000"),
            ("Trà đá x2", "10.000"),
            ("Tổng cộng", "160.000"),
            ("Tiền khách đưa", "200.000"),
            ("Tiền thừa", "40.000"),
        ]
        let size = CGSize(width: 900, height: 1_200)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 40, weight: .medium), .foregroundColor: UIColor.black,
            ]
            for (index, row) in rows.enumerated() {
                let y = 80 + CGFloat(index) * 120
                (row.0 as NSString).draw(at: CGPoint(x: 50, y: y), withAttributes: attributes)
                let width = (row.1 as NSString).size(withAttributes: attributes).width
                (row.1 as NSString).draw(at: CGPoint(x: size.width - 50 - width, y: y), withAttributes: attributes)
            }
        }
    }
}
#endif
