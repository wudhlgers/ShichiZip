import AppKit
import SwiftUI

struct PasswordVaultDetailPane: View {
    @ObservedObject var model: PasswordVaultLibraryModel

    private var item: PasswordVaultItem? {
        if model.sidebarSelection == .history, let usage = model.selectedUsage {
            return model.item(withID: usage.itemID)
        }
        return model.selectedItem
    }

    var body: some View {
        if let item {
            PasswordVaultItemDetailView(item: item, model: model)
                .id(item.id)
        } else {
            PasswordVaultEmptyState(
                systemImage: model.sidebarSelection == .history ? "list.bullet.rectangle" : "key.fill",
                title: model.sidebarSelection == .history
                    ? SZL10n.string("password.vault.history.selectTitle")
                    : SZL10n.string("password.vault.noSelectionTitle"),
                message: model.sidebarSelection == .history
                    ? SZL10n.string("password.vault.history.selectMessage")
                    : SZL10n.string("password.vault.noSelectionMessage"),
            )
        }
    }
}

private struct PasswordVaultItemDetailView: View {
    let item: PasswordVaultItem
    @ObservedObject var model: PasswordVaultLibraryModel

    @State private var revealed = false
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                passwordSection
                if !item.note.isEmpty {
                    section(SZL10n.string("password.vault.detail.notes")) {
                        Text(item.note)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !item.tags.isEmpty {
                    section(SZL10n.string("password.vault.detail.tags")) {
                        PasswordVaultTagChips(tags: item.tags)
                    }
                }
                archivesSection
                usageSection
                metadataSection
                actions
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.resolvedIconName)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 58, height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12)),
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 22, weight: .semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)

                if item.useCount > 0 {
                    Text(SZL10n.string("password.vault.detail.usedTimes", item.useCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Button {
                model.toggleFavorite(item)
            } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(item.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help(item.isFavorite
                ? SZL10n.string("password.vault.removeFavorite")
                : SZL10n.string("password.vault.addFavorite"))
            .accessibilityIdentifier("passwordVault.favorite")
        }
    }

    private var passwordSection: some View {
        section(SZL10n.string("password.vault.detail.password")) {
            HStack(spacing: 10) {
                Text(revealed ? item.password : item.maskedPassword)
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(SZL10n.string(revealed
                    ? "password.vault.hidePassword"
                    : "password.vault.showPassword"))
                .accessibilityIdentifier("passwordVault.reveal")

                Button {
                    model.copyPassword(item)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copied = false
                    }
                } label: {
                    Label(copied
                        ? SZL10n.string("password.vault.copied")
                        : SZL10n.string("password.vault.copyPassword"),
                    systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help(SZL10n.string("password.vault.copyHelp"))
                .accessibilityIdentifier("passwordVault.copy")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor)),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1),
            )
        }
    }

    private var archivesSection: some View {
        section(SZL10n.string("password.vault.detail.usedWith")) {
            let archives = model.archiveNames(for: item.id)
            if archives.isEmpty {
                Text(SZL10n.string("password.vault.detail.noArchives"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(archives, id: \.self) { archive in
                        HStack(spacing: 7) {
                            Image(systemName: "archivebox")
                                .foregroundStyle(.secondary)
                            Text(archive)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private var usageSection: some View {
        let records = Array(model.usage(for: item.id).prefix(8))
        return section(SZL10n.string("password.vault.detail.history")) {
            if records.isEmpty {
                Text(SZL10n.string("password.vault.detail.noHistory"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(records) { record in
                        HStack(spacing: 8) {
                            Text(record.date, format: .dateTime.year().month().day().hour().minute())
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 150, alignment: .leading)
                            Text(record.archiveName)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private var metadataSection: some View {
        section(SZL10n.string("password.vault.detail.info")) {
            VStack(alignment: .leading, spacing: 6) {
                metadataRow(SZL10n.string("password.vault.detail.created"), item.createdAt)
                metadataRow(SZL10n.string("password.vault.detail.updated"), item.updatedAt)
                if let lastUsedAt = item.lastUsedAt {
                    metadataRow(SZL10n.string("password.vault.detail.lastUsed"), lastUsedAt)
                }
                HStack(spacing: 6) {
                    Text(SZL10n.string("password.vault.detail.useCount"))
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                    Text("\(item.useCount)")
                }
                .font(.callout)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                model.beginEditing(item)
            } label: {
                Label(SZL10n.string("password.vault.edit"), systemImage: "pencil")
            }
            .keyboardShortcut("e", modifiers: .command)
            .accessibilityIdentifier("passwordVault.edit")

            Button(role: .destructive) {
                model.requestDelete([item])
            } label: {
                Label(SZL10n.string("password.vault.delete"), systemImage: "trash")
            }
            .accessibilityIdentifier("passwordVault.delete")

            Spacer()
        }
        .padding(.top, 4)
    }

    private func metadataRow(_ title: String, _ date: Date) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(date, format: .dateTime.year().month().day().hour().minute())
                .monospacedDigit()
        }
        .font(.callout)
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PasswordVaultTagChips: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.secondary.opacity(0.12)),
                    )
            }
        }
    }
}

/// Minimal wrapping layout so tags do not collapse into a single clipped row.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > width {
                maxWidth = max(maxWidth, currentX - spacing)
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        maxWidth = max(maxWidth, max(0, currentX - spacing))
        return CGSize(width: min(width, maxWidth), height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal _: ProposedViewSize,
                       subviews: Subviews,
                       cache _: inout ())
    {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
