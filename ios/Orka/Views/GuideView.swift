import SwiftUI
import OrkaCore

private struct RowsKey: Hashable {
    let group: String
    let filter: String
    let version: Int
    let favorites: Int
}

/// A run of channels under one header. Single-group views have one untitled section.
private struct GuideSection: Identifiable {
    let id: String
    let title: String?
    let channels: [Channel]
}

/// Channels with what's on now. "All channels" is split into one section per shown group, with
/// headers that stay pinned while you scroll; the tiles at the top jump straight to a group.
/// Guide data is only fetched for the rows on screen.
struct GuideView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""
    @State private var showGroups = false
    @State private var sections: [GuideSection] = []
    @State private var built = false
    @State private var buildCount = 0
    @State private var jumpTo: String?

    private var isAll: Bool { model.guideGroup == AppModel.allGroup }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Color.clear.frame(height: 0).id("top")
                        if !model.channels.isEmpty { groupTiles(proxy) }
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .onChange(of: buildCount) { performJump(proxy) }
            }
            .miniPlayerInset()
            .background(OrkaBackground())
            .navigationTitle(model.groupName(model.guideGroup))
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $filter, prompt: isAll ? "Filter channels" : "Filter this group")
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

    // MARK: Group tiles

    /// Your shown groups, in the provider's order.
    private var shownGroups: [ChannelCategory] {
        model.categories.filter { (model.library.counts[$0.id] ?? 0) > 0 && model.isGroupVisible($0.id) }
    }

    private func groupTiles(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                tile(id: AppModel.allGroup, name: "All channels", count: model.channels.count, proxy: proxy)
                if !model.favorites.isEmpty {
                    tile(id: AppModel.favoritesGroup, name: "★ Favorites", count: model.favorites.count, proxy: proxy)
                }
                ForEach(shownGroups) { c in
                    tile(id: c.id, name: c.name, count: model.library.counts[c.id] ?? 0, proxy: proxy)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func tile(id: String, name: String, count: Int, proxy: ScrollViewProxy) -> some View {
        let current = model.guideGroup == id
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            select(id, proxy: proxy)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(count) channel\(count == 1 ? "" : "s")").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 190, alignment: .leading)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .glassEffect(current ? .regular.tint(model.accent.opacity(0.35)).interactive() : .regular.interactive(), in: shape)
    }

    /// All / Favorites switch the view. A group tile jumps to that group's section in All channels.
    private func select(_ id: String, proxy: ScrollViewProxy) {
        if id == AppModel.allGroup || id == AppModel.favoritesGroup {
            model.guideGroup = id
            withAnimation { proxy.scrollTo("top", anchor: .top) }
            return
        }
        if isAll && sections.contains(where: { $0.id == id }) {
            withAnimation { proxy.scrollTo(id, anchor: .top) }
            return
        }
        // Not on screen yet: switch to All channels (clearing a filter that hides it), then jump.
        jumpTo = id
        if !isAll { model.guideGroup = AppModel.allGroup }
        if !filter.isEmpty { filter = "" }
    }

    private func performJump(_ proxy: ScrollViewProxy) {
        guard let id = jumpTo, sections.contains(where: { $0.id == id }) else { return }
        jumpTo = nil
        withAnimation { proxy.scrollTo(id, anchor: .top) }
    }

    // MARK: List

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
        } else if sections.isEmpty {
            Text(model.guideGroup == AppModel.favoritesGroup && filter.isEmpty
                 ? "No favorites yet. Touch and hold a channel to add one."
                 : "No channels match.")
                .foregroundStyle(.secondary)
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
        } else {
            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.channels) { channel in
                            // Channel up/down in the player stays within the group.
                            ChannelRow(channel: channel, queue: section.channels)
                        }
                    } header: {
                        if let title = section.title {
                            sectionHeader(title, count: section.channels.count)
                                .id(section.id)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.bold)).lineLimit(1)
            Spacer(minLength: 8)
            Text("\(count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.top, 6)
        .padding(.bottom, 2)
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

    // MARK: Building

    private func rebuild() async {
        let typed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            try? await Task.sleep(for: .milliseconds(180)) // wait for typing to settle
            if Task.isCancelled { return }
        }
        let group = model.guideGroup
        let list = model.channels(inGroup: group)
        let categories = model.categories
        let words = ChannelSearch.words(typed)
        let built = await Task.detached(priority: .userInitiated) { () -> [GuideSection] in
            let channels = words.isEmpty
                ? list
                : list.filter { ChannelSearch.matches(nameWords: ChannelSearch.words($0.name), queryWords: words) }
            guard group == AppModel.allGroup else {
                return channels.isEmpty ? [] : [GuideSection(id: group, title: nil, channels: channels)]
            }
            // One section per group, in the provider's group order.
            var byGroup: [String: [Channel]] = [:]
            for ch in channels { byGroup[ch.categoryId, default: []].append(ch) }
            var out: [GuideSection] = []
            for c in categories {
                if let chans = byGroup.removeValue(forKey: c.id) {
                    out.append(GuideSection(id: c.id, title: c.name, channels: chans))
                }
            }
            let leftovers = byGroup.values.flatMap { $0 }
            if !leftovers.isEmpty { out.append(GuideSection(id: "__other__", title: "Other", channels: leftovers)) }
            return out
        }.value
        if Task.isCancelled { return }
        sections = built
        self.built = true
        buildCount += 1
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
