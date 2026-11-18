import SwiftUI
import OrkaCore

private struct RowsKey: Hashable {
    let group: String
    let filter: String
    let version: Int
    let favorites: Int
}

/// Channels with what's on now, by group. Guide data is only fetched for the rows on screen.
struct GuideView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""
    @State private var showGroups = false
    @State private var rows: [Channel] = []
    @State private var built = false

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .miniPlayerInset()
            .background(OrkaBackground())
            .navigationTitle(model.groupName(model.guideGroup))
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $filter, prompt: "Filter this group")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showGroups = true
                    } label: {
                        Label("Groups", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showGroups) { GroupPicker() }
            .task(id: RowsKey(group: model.guideGroup, filter: filter, version: model.channelsVersion, favorites: model.favorites.count)) {
                await rebuild()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.channels.isEmpty && model.allChannelCount > 0 {
            VStack(spacing: 12) {
                Text("All channel groups are hidden").font(.headline)
                Button("Choose groups") { model.showSettings = true }
                    .buttonStyle(.glassProminent)
            }
            .padding(.top, 60)
            .frame(maxWidth: .infinity)
        } else if model.channels.isEmpty {
            emptyState
        } else if !built {
            Color.clear.frame(height: 1) // first build is a moment away; don't flash "no matches"
        } else if rows.isEmpty {
            Text(model.guideGroup == AppModel.favoritesGroup && filter.isEmpty
                 ? "No favorites yet. Touch and hold a channel to add one."
                 : "No channels match.")
                .foregroundStyle(.secondary)
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(rows) { channel in
                    ChannelRow(channel: channel, queue: rows)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 14) {
            switch model.syncStates[.live] ?? .idle {
            case .syncing:
                ProgressView()
                Text("Loading channels…").foregroundStyle(.secondary)
                Text("Big playlists can take a moment the first time.")
                    .font(.footnote).foregroundStyle(.tertiary)
            case .failed(let message):
                Text("Couldn't load channels").font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Try again") { Task { await model.refreshLive() } }
                    .buttonStyle(.glassProminent)
            case .idle:
                Text("No channels yet").font(.headline)
                Button("Sync Live TV") { Task { await model.refreshLive() } }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }

    private func rebuild() async {
        let typed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            try? await Task.sleep(for: .milliseconds(180)) // wait for typing to settle
            if Task.isCancelled { return }
        }
        let list = model.channels(inGroup: model.guideGroup)
        if typed.isEmpty {
            rows = list
            built = true
            return
        }
        let words = ChannelSearch.words(typed)
        let filtered = await Task.detached(priority: .userInitiated) { () -> [Channel] in
            list.filter { ChannelSearch.matches(nameWords: ChannelSearch.words($0.name), queryWords: words) }
        }.value
        if !Task.isCancelled {
            rows = filtered
            built = true
        }
    }
}

/// Pick which group of channels to browse.
struct GroupPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var categories: [ChannelCategory] {
        let counts = model.library.counts
        let all = model.categories.filter { (counts[$0.id] ?? 0) > 0 && model.isGroupVisible($0.id) }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return q.isEmpty ? all : all.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    if !model.favorites.isEmpty {
                        row(id: AppModel.favoritesGroup, name: "★ Favorites", count: model.favorites.count)
                    }
                    row(id: AppModel.allGroup, name: "All channels", count: model.channels.count)
                }
                ForEach(categories) { c in
                    row(id: c.id, name: c.name, count: model.library.counts[c.id] ?? 0)
                }
            }
            .scrollContentBackground(.hidden)
            .background(OrkaBackground())
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Find a group")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(id: String, name: String, count: Int) -> some View {
        Button {
            model.guideGroup = id
            dismiss()
        } label: {
            HStack {
                Text(name)
                Spacer()
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                if model.guideGroup == id {
                    Image(systemName: "checkmark").foregroundStyle(model.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
