import SwiftUI
import OrkaCore

struct SportsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if let updated = model.sportsUpdated {
                        Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    myTeams
                    let live = model.liveGames()
                    if !live.isEmpty { section("Live now", live) }
                    ForEach(League.allCases, id: \.self) { league in
                        let list = model.games[league] ?? []
                        if !list.isEmpty { section(league.label, model.sorted(list)) }
                    }
                    if model.games.isEmpty {
                        if model.sportsLoading {
                            HStack(spacing: 10) { ProgressView(); Text("Loading games…").foregroundStyle(.secondary) }
                        } else if let error = model.sportsError {
                            VStack(spacing: 12) {
                                Text(error).foregroundStyle(.secondary)
                                Button("Try again") { Task { await model.refreshSports() } }
                                    .buttonStyle(.glassProminent)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .miniPlayerInset()
            .background(OrkaBackground())
            .navigationTitle("Sports")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await model.refreshSports() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.setShowScores(!model.showScores)
                    } label: {
                        Image(systemName: model.showScores ? "eye" : "eye.slash")
                    }
                    .accessibilityLabel(model.showScores ? "Hide scores" : "Show scores")
                }
            }
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            // Scores keep updating while this tab is open: every 30 seconds during live games.
            .task {
                while !Task.isCancelled {
                    await model.refreshSports()
                    try? await Task.sleep(for: .seconds(model.anyLive ? 30 : 120))
                }
            }
        }
    }

    @ViewBuilder
    private var myTeams: some View {
        let mine = model.myGames()
        VStack(alignment: .leading, spacing: 12) {
            Text("My teams").font(.title3.bold())
            if model.favoriteTeams.isEmpty {
                Button {
                    model.showSettings = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add your teams").font(.headline)
                        Text("Pick favorites in Settings to see their games here.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(cornerRadius: 20, interactive: true)
                }
                .buttonStyle(.plain)
            } else if mine.isEmpty {
                Text("Your teams have no games today or coming up.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(mine) { game in
                    NavigationLink(value: game) { GameCard(game: game) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func section(_ title: String, _ games: [Game]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            ForEach(games) { game in
                NavigationLink(value: game) { GameCard(game: game) }.buttonStyle(.plain)
            }
        }
    }
}

/// One game with the channels that carry it.
struct GameDetailView: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        let g = model.currentGame(game)
        let showScore = model.showScores && g.state != .pre
        let matches = model.channels(for: g)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(g.league.label).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        StatusLabel(game: g)
                    }
                    TeamLine(team: g.away, game: g, showScore: showScore, big: true)
                    TeamLine(team: g.home, game: g, showScore: showScore, big: true)
                    if !g.networks.isEmpty {
                        Text("Broadcast: " + g.networks.joined(separator: ", "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 26)

                Button {
                    model.setShowScores(!model.showScores)
                } label: {
                    Label(model.showScores ? "Hide scores" : "Show scores", systemImage: model.showScores ? "eye.slash" : "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Watch on").font(.title3.bold())
                    if model.matcher == nil {
                        HStack(spacing: 10) { ProgressView(); Text("Finding channels…").foregroundStyle(.secondary) }
                    } else if matches.isEmpty {
                        Text("Orka couldn't find a channel carrying this game. Try searching your channels:")
                            .font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            searchButton(g.away.team.nickname)
                            searchButton(g.home.team.nickname)
                            if let n = g.networks.first { searchButton(n) }
                        }
                    } else {
                        Text("Best matches from your playlist").font(.footnote).foregroundStyle(.secondary)
                        ForEach(matches) { ch in
                            ChannelRow(channel: ch, queue: matches)
                        }
                    }
                }
            }
            .padding(16)
        }
        .miniPlayerInset()
        .background(OrkaBackground())
        .navigationTitle(g.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(model.currentGame(game).state == .live ? 30 : 120))
                if Task.isCancelled { break }
                await model.refreshSports()
            }
        }
    }

    private func searchButton(_ text: String) -> some View {
        Button(text) {
            model.searchQuery = text
            model.tab = .search
        }
        .buttonStyle(.glass)
        .lineLimit(1)
    }
}
