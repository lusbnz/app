import SwiftUI

/// Tỷ giá để quy ngoại tệ gõ vào ("20 usd") ra đồng. Nhẩm không có mạng nên tỷ giá do bạn tự chỉnh.
struct ExchangeRatesView: View {
    @State private var texts: [Currency: String] = [:]
    @FocusState private var focused: Currency?

    var body: some View {
        Form {
            Section {
                ForEach(Currency.allCases) { currency in
                    HStack {
                        Text(currency.code)
                        Spacer(minLength: 16)
                        TextField(format(currency.defaultRate), text: binding(currency))
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .keyboardType(.decimalPad)
                            .focused($focused, equals: currency)
                            .frame(maxWidth: 140)
                        Text("đ").foregroundStyle(Color.xuTextSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Đồng cho một đơn vị")
            } footer: {
                Text("Gõ “20 usd”, “$20”, “5 euro” hay “1000 yên”, Nhẩm quy ra đồng theo tỷ giá này và ghi kèm số gốc. Tỷ giá để trống là giá trị gần đúng có sẵn, nên hãy chỉnh cho sát.")
            }
            .listRowBackground(Color.xuSurface)
            Section {
                Button("Về tỷ giá có sẵn", role: .destructive) {
                    texts = [:]
                    ExchangeRates.standard.save()
                }
            }
            .listRowBackground(Color.xuSurface)
        }
        .scrollContentBackground(.hidden)
        .xuScreen()
        .navigationTitle("Tỷ giá ngoại tệ")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let rates = ExchangeRates.load()
            texts = Dictionary(uniqueKeysWithValues: rates.overrides.map { ($0.key, format($0.value)) })
        }
        .onChange(of: texts) { _, _ in save() }
    }

    private func binding(_ currency: Currency) -> Binding<String> {
        Binding { texts[currency] ?? "" } set: { texts[currency] = $0 }
    }

    private func format(_ rate: Decimal) -> String {
        let whole = NSDecimalNumber(decimal: rate).intValue
        return Decimal(whole) == rate ? MoneyFormatter.grouped(whole) : "\(rate)"
    }

    private func save() {
        var overrides: [Currency: Decimal] = [:]
        for (currency, text) in texts {
            if let rate = ExchangeRates.parseRate(text) { overrides[currency] = rate }
        }
        ExchangeRates(overrides: overrides).save()
    }
}

#Preview {
    NavigationStack { ExchangeRatesView() }.xuPreview()
}
