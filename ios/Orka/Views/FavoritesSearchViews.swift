import SwiftUI
import OrkaCore

struct FavoritesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                if model.favorites.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "star").font(.largeTitle).foregroundStyle(.secondary)
                        Text("No favorites yet").font(.headline)
                        Text("Touch and hold any channel, then choose Add to Favorites.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 80)
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(model.favorites) { channel in
                            ChannelRow(channel: channel, queue: model.favorites)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .miniPlayerInset()
            .background(OrkaBackground())
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var results: [Channel] = []

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if model.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Search all your channels by name. Try ESPN, Fox or NBC.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)
                    } else if results.isEmpty {
                        Text("No channels match \"\(model.searchQuery)\".")
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)
                    } else {
                        Text("\(results.count) results").font(.footnote).foregroundStyle(.secondary)
                        LazyVStack(spacing: 8) {
                            ForEach(results) { channel in
                                ChannelRow(channel: channel, queue: results)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .miniPlayerInset()
            .background(OrkaBackground())
            .navigationTitle("Search")
            .searchable(text: $model.searchQuery, prompt: "Channel name")
            .task(id: model.searchQuery) {
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
                results = model.search(model.searchQuery)
            }
        }
    }
}
