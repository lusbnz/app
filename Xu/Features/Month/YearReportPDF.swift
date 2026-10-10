import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Tệp PDF chỉ được dựng khi người dùng chọn nơi chia sẻ.
struct YearReportExport: Transferable {
    let report: YearReport
    let categoryTitles: [String: String]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { export in
            let url = try await MainActor.run {
                try YearReportPDF.write(export.report, categoryTitles: export.categoryTitles, calendar: .current)
            }
            return SentTransferredFile(url)
        }
    }
}

/// Dựng báo cáo năm thành PDF khổ A4, hai trang, chữ là vector. Màu cố định (nền trắng) để in được, không theo chủ đề của app.
@MainActor
enum YearReportPDF {
    /// A4 ở 72 điểm mỗi inch.
    static let pageSize = CGSize(width: 595, height: 842)

    enum Failure: Error {
        case cannotCreateFile
    }

    /// "pennyline-bao-cao-2026.pdf"
    nonisolated static func fileName(year: Int) -> String {
        "pennyline-bao-cao-\(year).pdf"
    }

    /// Ghi vào thư mục tạm (hoặc `directory`) và trả về đường dẫn.
    static func write(
        _ report: YearReport, categoryTitles: [String: String], calendar: Calendar,
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let url = directory.appendingPathComponent(fileName(year: report.year))
        var box = CGRect(origin: .zero, size: pageSize)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { throw Failure.cannotCreateFile }
        let pages: [AnyView] = [
            AnyView(YearReportPage.Overview(report: report, categoryTitles: categoryTitles)),
            AnyView(YearReportPage.Rankings(report: report, calendar: calendar)),
        ]
        for page in pages {
            let renderer = ImageRenderer(
                content: page
                    .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
            )
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return url
    }
}

/// Các trang của bản PDF.
enum YearReportPage {
    static let ink = Color(red: 0.16, green: 0.14, blue: 0.27)
    static let muted = Color(red: 0.42, green: 0.41, blue: 0.50)
    static let bar = Color(red: 0.56, green: 0.50, blue: 0.84)
    static let highlight = Color(red: 0.99, green: 0.87, blue: 0.52)
    static let rule = Color(red: 0.88, green: 0.87, blue: 0.93)

    static func title(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(ink)
    }

    /// Trang 1: tổng, từng tháng, danh mục.
    struct Overview: View {
        let report: YearReport
        let categoryTitles: [String: String]

        var body: some View {
            let largestMonth = max(1, report.months.map(\.total).max() ?? 1)
            let largestCategory = max(1, report.byCategory.first?.total ?? 1)
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Pennyline")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(YearReportPage.muted)
                    Text("Báo cáo năm \(String(report.year))")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(YearReportPage.ink)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: MoneyFormatter.full(report.total))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(YearReportPage.ink)
                        .padding(.horizontal, 4)
                        .background(alignment: .bottom) {
                            Rectangle().fill(YearReportPage.highlight).frame(height: 16).offset(y: -6)
                        }
                    Text(verbatim: YearReportText.summary(report))
                    if let change = YearReportText.change(report) { Text(verbatim: change) }
                    if report.outsideBudgetTotal > 0 {
                        Text("Trong đó \(MoneyFormatter.short(report.outsideBudgetTotal)) ngoài ngân sách.")
                    }
                }
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(YearReportPage.muted)

                VStack(alignment: .leading, spacing: 10) {
                    YearReportPage.title(String(localized: "Từng tháng"))
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(report.months) { month in
                            VStack(spacing: 4) {
                                Text(verbatim: month.total > 0 ? MoneyFormatter.short(month.total) : "")
                                    .font(.system(size: 7, design: .rounded))
                                    .foregroundStyle(YearReportPage.muted)
                                    .lineLimit(1)
                                    .fixedSize()
                                Rectangle()
                                    .fill(month.month == report.busiestMonth ? YearReportPage.highlight : YearReportPage.bar)
                                    .frame(height: month.total > 0 ? max(2, 120 * CGFloat(month.total) / CGFloat(largestMonth)) : 1)
                                Text(verbatim: "\(month.month)")
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(YearReportPage.muted)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 150, alignment: .bottom)
                }

                VStack(alignment: .leading, spacing: 8) {
                    YearReportPage.title(String(localized: "Danh mục"))
                    ForEach(report.byCategory.prefix(12)) { group in
                        HStack(spacing: 10) {
                            Text(verbatim: categoryTitles[group.key] ?? group.label)
                                .frame(width: 130, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { proxy in
                                Rectangle()
                                    .fill(YearReportPage.bar)
                                    .frame(width: max(2, proxy.size.width * CGFloat(group.total) / CGFloat(largestCategory)))
                            }
                            .frame(height: 8)
                            Text(verbatim: "\(report.share(of: group))%")
                                .foregroundStyle(YearReportPage.muted)
                                .frame(width: 34, alignment: .trailing)
                            Text(verbatim: MoneyFormatter.full(group.total))
                                .frame(width: 96, alignment: .trailing)
                        }
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(YearReportPage.ink)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(48)
        }
    }

    /// Trang 2: khoản và nơi tốn nhiều nhất, điểm đáng nhớ.
    struct Rankings: View {
        let report: YearReport
        let calendar: Calendar

        var body: some View {
            VStack(alignment: .leading, spacing: 22) {
                table(String(localized: "Tốn nhiều nhất"), report.topNames)
                table(String(localized: "Chi ở đâu nhiều nhất"), report.topPlaces)
                VStack(alignment: .leading, spacing: 6) {
                    YearReportPage.title(String(localized: "Đáng nhớ"))
                    ForEach(YearReportText.highlights(report, calendar: calendar), id: \.self) { line in
                        Text(verbatim: line)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(YearReportPage.ink)
                    }
                }
                Spacer(minLength: 0)
                Text("Tạo bằng Pennyline. Số liệu gồm mọi khoản chi đã ghi, kể cả khoản ngoài ngân sách.")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(YearReportPage.muted)
            }
            .padding(48)
        }

        @ViewBuilder
        private func table(_ title: String, _ groups: [YearReport.Group]) -> some View {
            if !groups.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    YearReportPage.title(title)
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        VStack(spacing: 6) {
                            HStack(spacing: 10) {
                                Text(verbatim: "\(index + 1)")
                                    .foregroundStyle(YearReportPage.muted)
                                    .frame(width: 18, alignment: .leading)
                                Text(verbatim: group.label)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(group.count) lần")
                                    .foregroundStyle(YearReportPage.muted)
                                Text(verbatim: MoneyFormatter.full(group.total))
                                    .frame(width: 96, alignment: .trailing)
                            }
                            Rectangle().fill(YearReportPage.rule).frame(height: 1)
                        }
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(YearReportPage.ink)
                    }
                }
            }
        }
    }
}
