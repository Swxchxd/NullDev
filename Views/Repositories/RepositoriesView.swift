import SwiftUI
#if SWIFT_PACKAGE
import NullDevCore
#endif

struct RepositoriesView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                PageHeader(title: "Repositories", subtitle: "Your code, within reach. \(store.repositories.count.formatted()) repositories loaded.")
                HStack {
                    Picker("Language", selection: $store.repositoryQuery.language) {
                        Text("All languages").tag("All languages")
                        ForEach(store.languages, id: \.self) { Text($0).tag($0) }
                    }.frame(maxWidth: 210)
                    Picker("Sort", selection: $store.repositoryQuery.sort) {
                        ForEach(RepositorySort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.frame(maxWidth: 210)
                    Spacer()
                    Toggle("Favorites", systemImage: "star", isOn: $store.repositoryQuery.favoritesOnly).toggleStyle(.button)
                }
            }.padding(24)
            Divider()
            List {
                ForEach(store.filteredRepositories) { repo in
                    NavigationLink(value: repo) {
                        HStack {
                            RepositoryRow(repository: repo)
                            Button { store.toggleFavorite(repo) } label: {
                                Image(systemName: store.favorites.contains(repo.id) ? "star.fill" : "star")
                                    .foregroundStyle(store.favorites.contains(repo.id) ? Color.yellow : Color.secondary)
                            }.buttonStyle(.borderless).help("Toggle favorite").accessibilityLabel("Favorite \(repo.name)")
                        }
                    }.modifier(RepositoryContext(repository: repo))
                }
            }.listStyle(.inset)
            .overlay {
                if store.filteredRepositories.isEmpty && !store.loading {
                    EmptyState(title: "No repositories", symbol: "books.vertical", detail: "Try another search or filter. Private repositories require a token with access.")
                }
            }
        }
        .searchable(text: $store.repositoryQuery.search, prompt: "Search repositories")
    }
}
