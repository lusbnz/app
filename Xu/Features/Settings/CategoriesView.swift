import SwiftData
import SwiftUI

/// Danh mục tự thêm và các luật Xu đã học: thêm, đổi tên, đổi danh mục của luật, xóa.
struct CategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomCategory.createdAt) private var customCategories: [CustomCategory]
    @Query(sort: \CategoryRule.keyword) private var rules: [CategoryRule]
    @State private var categoryForm: CategoryForm?
    @State private var ruleForm: RuleForm?
    @State private var pendingDelete: CustomCategory?
    @State private var reapply: ReapplyOffer?

    private var catalog: CategoryCatalog { CategoryCatalog(custom: customCategories) }
    private var recorder: ExpenseRecorder { ExpenseRecorder(context: modelContext) }

    var body: some View {
        let catalog = catalog
        List {
            Section {
                ForEach(customCategories) { category in
                    Button { categoryForm = CategoryForm(editing: category) } label: {
                        CategoryLabel(category: catalog.info(for: category.key)).foregroundStyle(Color.xuTextPrimary)
                    }
                    .swipeActions {
                        Button("Xóa", role: .destructive) { pendingDelete = category }
                    }
                }
                Button("Thêm danh mục") { categoryForm = CategoryForm(editing: nil) }
            } header: {
                Text("Danh mục của bạn")
            } footer: {
                Text("Xóa một danh mục thì các khoản đã gán chuyển về “khác”.")
            }
            .listRowBackground(Color.xuSurface)

            Section {
                ForEach(rules) { rule in
                    Button { ruleForm = RuleForm(editing: rule) } label: {
                        HStack {
                            Text(rule.keyword).foregroundStyle(Color.xuTextPrimary)
                            Spacer()
                            CategoryLabel(category: catalog.info(for: rule.categoryKey))
                                .foregroundStyle(Color.xuTextSecondary)
                        }
                    }
                    .swipeActions {
                        Button("Xóa", role: .destructive) { recorder.deleteRule(rule) }
                    }
                }
                Button("Thêm luật") { ruleForm = RuleForm(editing: nil) }
            } header: {
                Text("Luật đã học")
            } footer: {
                Text("Khoản có tên chứa từ khóa sẽ tự vào danh mục tương ứng. Từ khóa không phân biệt hoa thường và dấu.")
            }
            .listRowBackground(Color.xuSurface)
        }
        .scrollContentBackground(.hidden)
        .xuScreen()
        .navigationTitle("Danh mục và luật")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $categoryForm) { form in
            CategoryFormView(form: form, existingNames: catalog.all.map(\.title))
        }
        .sheet(item: $ruleForm) { form in
            RuleFormView(form: form) { reapply = $0 }
        }
        .reapplyDialog($reapply)
        .confirmationDialog(
            "Xóa danh mục?", isPresented: Binding { pendingDelete != nil } set: { if !$0 { pendingDelete = nil } },
            titleVisibility: .visible, presenting: pendingDelete
        ) { category in
            Button("Xóa “\(category.name)”", role: .destructive) { recorder.deleteCategory(category) }
        } message: { _ in
            Text("Các khoản và luật đang dùng danh mục này sẽ chuyển về “khác”.")
        }
    }
}

struct CategoryForm: Identifiable {
    let id = UUID()
    var editing: CustomCategory?
}

struct RuleForm: Identifiable {
    let id = UUID()
    var editing: CategoryRule?
}

struct CategoryFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let form: CategoryForm
    let existingNames: [String]
    /// Gọi khi vừa thêm xong một danh mục mới (không gọi khi đổi tên).
    var onAdded: ((CustomCategory) -> Void)?
    @State private var name = ""
    @State private var iconName = CategoryIcon.fallback
    /// Người dùng đã tự chọn biểu tượng thì thôi không gợi ý theo tên nữa.
    @State private var pickedIcon = false
    @State private var failure: CategoryNaming.Failure?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Thú cưng", text: $name)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .onChange(of: name) { _, newName in
                            if !pickedIcon { iconName = CategoryIcon.suggest(for: newName) }
                        }
                } footer: {
                    if let failure { Text(Self.message(failure)).foregroundStyle(Color.red) }
                }
                .listRowBackground(Color.xuSurface)
                Section("Biểu tượng") {
                    iconGrid
                }
                .listRowBackground(Color.xuSurface)
            }
            .scrollContentBackground(.hidden)
            .xuScreen()
            .navigationTitle(form.editing == nil ? "Danh mục mới" : "Đổi tên")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu", action: save) }
            }
            .onAppear {
                guard let category = form.editing else { return }
                name = category.name
                iconName = CategoryIcon.resolved(category.iconName)
                pickedIcon = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
            ForEach(CategoryIcon.palette, id: \.self) { symbol in
                let isSelected = symbol == iconName
                Button {
                    iconName = symbol
                    pickedIcon = true
                } label: {
                    Image(systemName: symbol)
                        .font(.body)
                        .foregroundStyle(isSelected ? Color.xuOnButton : Color.xuTextPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isSelected ? Color.xuButton : Color.clear, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: symbol))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        let recorder = ExpenseRecorder(context: modelContext)
        let result: Result<Void, CategoryNaming.Failure>
        if let category = form.editing {
            result = recorder.renameCategory(category, to: name, existing: existingNames, iconName: iconName)
        } else {
            result = recorder.addCategory(name: name, existing: existingNames, iconName: iconName).map { onAdded?($0) }
        }
        switch result {
        case .success: dismiss()
        case .failure(let failure): self.failure = failure
        }
    }

    private static func message(_ failure: CategoryNaming.Failure) -> String {
        switch failure {
        case .empty: String(localized: "Hãy nhập tên danh mục.")
        case .tooLong: String(localized: "Tên tối đa \(CategoryNaming.maxLength) ký tự.")
        case .duplicate: String(localized: "Đã có danh mục tên này.")
        }
    }
}

private struct RuleFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let form: RuleForm
    /// Gọi sau khi lưu, kèm đề nghị áp luật cho khoản cũ nếu có.
    let onSaved: (ReapplyOffer?) -> Void
    @State private var keyword = ""
    @State private var categoryKey = SpendingCategory.other.rawValue
    @State private var showsEmptyError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("trà sữa", text: $keyword)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .disabled(form.editing != nil)
                } header: {
                    Text("Từ khóa")
                } footer: {
                    if showsEmptyError { Text("Hãy nhập từ khóa.").foregroundStyle(Color.red) }
                }
                .listRowBackground(Color.xuSurface)
                Section("Danh mục") {
                    CategoryChips(selection: $categoryKey)
                }
                .listRowBackground(Color.xuSurface)
            }
            .scrollContentBackground(.hidden)
            .xuScreen()
            .navigationTitle(form.editing == nil ? "Luật mới" : "Sửa luật")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu", action: save) }
            }
            .onAppear {
                if let rule = form.editing {
                    keyword = rule.keyword
                    categoryKey = rule.categoryKey
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let recorder = ExpenseRecorder(context: modelContext)
        if recorder.setRule(keyword: keyword, categoryKey: categoryKey) {
            onSaved(recorder.reapplyOffer(keyword: keyword, categoryKey: categoryKey))
            dismiss()
        } else {
            showsEmptyError = true
        }
    }
}

#Preview {
    NavigationStack { CategoriesView() }.xuPreview()
}
