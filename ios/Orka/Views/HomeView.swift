import SwiftUI
import OrkaCore

/// The front door: a short look at live games, what you watched lately, and your favorites.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    sportsSection
                    channelSection(
                        title: "Recently watched",
                        channels: model.recents,
                        emptyText: "Channels you watch show up here so you can jump back in."
                    )
                    channelSection(
                        title: "Favorites",
                        channels: model.favorites,
                        emptyText: "Touch and hold any channel, then choose Add to Favorites.",
                        actionTitle: model.favorites.isEmpty ? nil : "See all",
                        action: { model.tab = .favorites }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .miniPlayerInset()
            .background(OrkaBackground())
            .refreshable { await model.refreshSports() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Image("orka_mark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 27)
                        Text("Orka").font(.title3.bold())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
        }
    }

    @ViewBuilder
    private var sportsSection: some View {
        let home = model.homeGames()
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: home.title, actionTitle: "All sports") { model.tab = .sports }
            if home.games.isEmpty {
                if model.sportsUpdated == nil || model.sportsLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading scores…").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    Text(model.sportsError ?? "No games right now.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            } else {
                ForEach(home.games) { game in
                    NavigationLink(value: game) {
                        GameSummaryRow(game: game)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func channelSection(
        title: String,
        channels: [Channel],
        emptyText: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, actionTitle: actionTitle, action: action)
            if channels.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listPanel()
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(channels) { channel in
                            ChannelCard(channel: channel, queue: channels)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }
}
