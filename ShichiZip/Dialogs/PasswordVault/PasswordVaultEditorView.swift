import SwiftUI

struct PasswordVaultEditorView: View {
    @ObservedObject var model: PasswordVaultLibraryModel
    let context: PasswordVaultEditorContext

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var password: String
    @State private var iconName: String?
    @State private var note: String
    @State private var tags: [String]
    @State private var newTag = ""
    @State private var isFavorite: Bool
    @State private var showsPassword = false
    @State private var errorMessage: String?

    init(model: PasswordVaultLibraryModel, context: PasswordVaultEditorContext) {
        self.model = model
        self.context = context
        _title = State(initialValue: context.draft.title)
        _password = State(initialValue: context.draft.password)
        _iconName = State(initialValue: context.draft.iconName)
        _note = State(initialValue: context.draft.note)
        _tags = State(initialValue: context.draft.tags)
        _isFavorite = State(initialValue: context.draft.isFavorite)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(context.itemID == nil
                    ? SZL10n.string("password.vault.add")
                    : SZL10n.string("password.vault.edit"))
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleAndPassword
                    favoriteAndIcon
                    tagsAndNotes
                }
                .padding(20)
            }

            Divider()

            HStack(spacing: 10) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                Button(SZL10n.string("common.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(context.itemID == nil
                    ? SZL10n.string("password.vault.add")
                    : SZL10n.string("password.vault.save"))
                {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("passwordVault.editor.save")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 620, height: 650)
    }

    private var titleAndPassword: some View {
        VStack(alignment: .leading, spacing: 14) {
            editorSection(SZL10n.string("password.vault.field.title")) {
                TextField(SZL10n.string("password.vault.field.titlePlaceholder"), text: $title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("passwordVault.editor.title")
            }

            editorSection(SZL10n.string("password.vault.field.password")) {
                HStack(spacing: 8) {
                    Group {
                        if showsPassword {
                            TextField(SZL10n.string("password.vault.field.passwordPlaceholder"), text: $password)
                                .accessibilityIdentifier("passwordVault.editor.password")
                        } else {
                            SecureField(SZL10n.string("password.vault.field.passwordPlaceholder"), text: $password)
                                .accessibilityIdentifier("passwordVault.editor.password")
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button {
                        showsPassword.toggle()
                    } label: {
                        Image(systemName: showsPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(SZL10n.string(showsPassword
                        ? "password.vault.hidePassword"
                        : "password.vault.showPassword"))
                }
            }
        }
    }

    private var favoriteAndIcon: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(SZL10n.string("password.vault.favorite"), isOn: $isFavorite)
                .accessibilityIdentifier("passwordVault.editor.favorite")

            editorSection(SZL10n.string("password.vault.field.icon")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 8)], spacing: 8) {
                    iconButton(name: nil, systemImage: PasswordVaultIcon.default)
                    ForEach(PasswordVaultIconCatalog.selectable, id: \.self) { name in
                        iconButton(name: name, systemImage: name)
                    }
                }
            }
        }
    }

    private var tagsAndNotes: some View {
        VStack(alignment: .leading, spacing: 14) {
            editorSection(SZL10n.string("password.vault.field.tags")) {
                VStack(alignment: .leading, spacing: 8) {
                    if !tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text(tag)
                                    Button {
                                        tags.removeAll { $0 == tag }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField(SZL10n.string("password.vault.field.addTag"), text: $newTag)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addTag)
                            .accessibilityIdentifier("passwordVault.editor.tagField")
                        Button(SZL10n.string("password.vault.field.addTag"), action: addTag)
                            .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            editorSection(SZL10n.string("password.vault.field.notes")) {
                TextEditor(text: $note)
                    .font(.callout)
                    .frame(minHeight: 96)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor)),
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1),
                    )
                    .accessibilityIdentifier("passwordVault.editor.notes")
            }
        }
    }

    private func iconButton(name: String?, systemImage: String) -> some View {
        let selected = iconName == name
        return Button {
            iconName = name
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .frame(width: 34, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.20) : Color.secondary.opacity(0.08)),
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5),
                )
        }
        .buttonStyle(.plain)
        .help(name == nil
            ? SZL10n.string("password.vault.field.useDefaultIcon")
            : systemImage)
    }

    private func editorSection<Content: View>(_ title: String,
                                               @ViewBuilder content: () -> Content) -> some View
    {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        newTag = ""
    }

    private func save() {
        let draft = PasswordVaultItemDraft(
            title: title,
            password: password,
            category: context.draft.category,
            iconName: iconName,
            note: note,
            tags: tags,
            isFavorite: isFavorite,
        )

        do {
            if let itemID = context.itemID {
                try model.updateItem(id: itemID, with: draft)
            } else {
                try model.addItem(draft)
            }
            dismiss()
        } catch {
            errorMessage = (error as? PasswordVaultError)?.message ?? error.localizedDescription
        }
    }
}
