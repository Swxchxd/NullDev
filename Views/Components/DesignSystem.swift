import SwiftUI
import AppKit
#if SWIFT_PACKAGE
import NullDevCore
#endif

enum Theme {
    static let accent = Color(red: 0.39, green: 0.43, blue: 0.91)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Panel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title { Text(title).font(.headline).accessibilityAddTraits(.isHeader) }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.07)))
    }
}

struct ErrorNotice: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.callout).foregroundStyle(.orange).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Error: \(message)")
    }
}

struct EmptyState: View {
    let title: String
    let symbol: String
    let detail: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(detail))
            .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct Avatar: View {
    let url: URL?
    var size: CGFloat = 40
    @State private var bitmap: NSImage?
    var body: some View {
        Group {
            if let bitmap { Image(nsImage: bitmap).resizable().scaledToFill() }
            else { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.tertiary) }
        }
        .frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
        .task(id: url) {
            bitmap = nil
            if let url, let data = try? await AvatarCache.shared.data(for: url), !Task.isCancelled { bitmap = NSImage(data: data) }
        }
    }
}

struct MetaLabel: View {
    let value: String
    let symbol: String
    var body: some View { Label(value, systemImage: symbol).font(.caption).foregroundStyle(.secondary) }
}

struct Tag: View {
    let text: String
    var color: Color = .secondary
    var textColor: Color?
    var body: some View {
        Text(text).font(.caption).lineLimit(1).padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(textColor ?? color).background(color.opacity(0.10), in: Capsule())
    }
}

struct RepositoryRow: View {
    let repository: Repository
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: repository.isPrivate ? "lock" : "book.closed")
                .font(.title3).foregroundStyle(Theme.accent).frame(width: 25).padding(.top, 2)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(repository.fullName).font(.headline).lineLimit(1)
                    Tag(text: repository.isPrivate ? "Private" : "Public")
                    if repository.archived == true { Tag(text: "Archived", color: .orange) }
                }
                if let description = repository.description, !description.isEmpty {
                    Text(description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 14) {
                    if let language = repository.language { MetaLabel(value: language, symbol: "circle.fill") }
                    MetaLabel(value: repository.stargazersCount.formatted(), symbol: "star")
                    MetaLabel(value: repository.forksCount.formatted(), symbol: "tuningfork")
                    MetaLabel(value: "\(repository.openIssuesCount) issues + PRs", symbol: "circle.dotted.circle")
                    if let updated = repository.updatedAt { Text(updated, style: .relative).font(.caption).foregroundStyle(.tertiary) }
                }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }
}

struct RepositoryContext: ViewModifier {
    let repository: Repository
    @Environment(AppStore.self) private var store
    func body(content: Content) -> some View {
        content.contextMenu {
            Link("Open on GitHub", destination: repository.htmlUrl)
            Button(store.favorites.contains(repository.id) ? "Remove Favorite" : "Add Favorite", systemImage: "star") { store.toggleFavorite(repository) }
            Button("Copy Repository URL", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(repository.htmlUrl.absoluteString, forType: .string)
            }
        }
    }
}
