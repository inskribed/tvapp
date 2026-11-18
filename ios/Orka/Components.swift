import SwiftUI
import OrkaCore

// MARK: Small pieces

struct ChannelLogo: View {
    let channel: Channel
    var width: CGFloat = 56
    var height: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08))
            if let s = channel.logo, let url = URL(string: s) {
                RemoteImage(url: url) { initials }
                    .padding(4)
            } else {
                initials
            }
        }
        .frame(width: width, height: height)
    }

    private var initials: some View {
        Text(String(channel.name.filter { $0.isLetter || $0.isNumber }.prefix(2)).uppercased())
            .font(.caption.bold())
            .foregroundStyle(.secondary)
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.medium))
            }
        }
    }
}

struct ProgressBar: View {
    @Environment(AppModel.self) private var model
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [model.accent, model.highlight], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, geo.size.width * value))
            }
        }
        .frame(height: 3)
    }
}

// MARK: Channels

/// One channel with what's on now. Touch and hold for favorites.
struct ChannelRow: View {
    @Environment(AppModel.self) private var model
    let channel: Channel
    let queue: [Channel]

    var body: some View {
        let nn = model.nowNext(channel)
        Button {
            model.play(channel, in: queue)
        } label: {
            HStack(spacing: 12) {
                ChannelLogo(channel: channel)
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if let now = nn.now {
                        Text(now.title)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        ProgressBar(value: now.progress(at: Date()))
                    } else if channel.epgId == nil || channel.epgId?.isEmpty == true {
                        Text("No guide info").font(.footnote).foregroundStyle(.tertiary)
                    } else if model.epg[channel.id] == nil {
                        Text("Loading…").font(.footnote).foregroundStyle(.tertiary)
                    } else {
                        Text("No guide info right now").font(.footnote).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
                if model.isFavorite(channel) {
                    Image(systemName: "star.fill").foregroundStyle(Brand.star).font(.footnote)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listPanel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                model.toggleFavorite(channel)
            } label: {
                Label(model.isFavorite(channel) ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: model.isFavorite(channel) ? "star.slash" : "star")
            }
        }
        .task(id: channel.id) {
            // Waits a moment so fast scrolling doesn't ask for every channel along the way.
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { await model.ensureEpg(channel) }
        }
    }
}

/// Compact card for the Home screen's horizontal lists.
struct ChannelCard: View {
    @Environment(AppModel.self) private var model
    let channel: Channel
    let queue: [Channel]

    var body: some View {
        let now = model.nowNext(channel).now
        Button {
            model.play(channel, in: queue)
        } label: {
            VStack(spacing: 8) {
                ChannelLogo(channel: channel, width: 96, height: 60)
                Text(channel.name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text(now?.title ?? " ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(width: 136)
            .glassCard(cornerRadius: 20, interactive: true)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                model.toggleFavorite(channel)
            } label: {
                Label(model.isFavorite(channel) ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: model.isFavorite(channel) ? "star.slash" : "star")
            }
        }
        .task(id: channel.id) {
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { await model.ensureEpg(channel) }
        }
    }
}

// MARK: Games

func startLabel(_ d: Date) -> String {
    if d.timeIntervalSince1970 == 0 { return "Upcoming" }
    let time = d.formatted(date: .omitted, time: .shortened)
    let cal = Calendar.current
    if cal.isDateInToday(d) { return "Today \(time)" }
    if cal.isDateInTomorrow(d) { return "Tomorrow \(time)" }
    return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + ", " + time
}

struct StatusLabel: View {
    let game: Game

    var body: some View {
        switch game.state {
        case .live:
            HStack(spacing: 5) {
                Circle().fill(Brand.live).frame(width: 7, height: 7)
                Text(game.detail.isEmpty ? "Live" : game.detail)
                    .foregroundStyle(Brand.live)
            }
            .font(.caption.weight(.semibold))
        case .pre:
            Text(startLabel(game.start)).font(.caption).foregroundStyle(.secondary)
        case .post:
            Text(game.detail.hasPrefix("Final") ? game.detail : "Final")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TeamLine: View {
    let team: GameTeam
    let game: Game
    let showScore: Bool
    var big = false

    var body: some View {
        let other = team.home ? game.away : game.home
        let leading = showScore && game.state == .post && (Int(team.score ?? "") ?? 0) > (Int(other.score ?? "") ?? 0)
        HStack(spacing: 10) {
            TeamLogo(team: team.team, size: big ? 40 : 24)
            Text(big ? team.team.displayName : team.team.shortName)
                .font(big ? Font.title3 : Font.body)
                .fontWeight(leading ? Font.Weight.bold : Font.Weight.medium)
                .lineLimit(1)
            Spacer(minLength: 8)
            if showScore, let score = team.score {
                Text(score).font(big ? Font.title.bold() : Font.headline.bold()).monospacedDigit()
            } else if game.state == .pre, let record = team.record {
                Text(record).font(big ? Font.subheadline : Font.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct TeamLogo: View {
    let team: Team
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let s = team.logo, let url = URL(string: s) {
                RemoteImage(url: url) { Circle().fill(.white.opacity(0.12)) }
            } else {
                Circle().fill(.white.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Full game card for the Sports tab.
struct GameCard: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        let showScore = model.showScores && game.state != .pre
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(game.league.label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                StatusLabel(game: game)
            }
            TeamLine(team: game.away, game: game, showScore: showScore)
            TeamLine(team: game.home, game: game, showScore: showScore)
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
        .contentShape(Rectangle())
    }

    private var footer: String {
        let net = game.networks.prefix(2).joined(separator: ", ")
        var parts: [String] = []
        if !net.isEmpty { parts.append(net) }
        if model.matcher != nil {
            let n = model.channels(for: game).count
            parts.append(n == 0 ? "No channel found" : (n == 1 ? "1 channel" : "\(n) channels"))
        }
        return parts.joined(separator: "  ·  ")
    }
}

/// Short version for the Home screen.
struct GameSummaryRow: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        let showScore = model.showScores && game.state != .pre
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                TeamLine(team: game.away, game: game, showScore: showScore)
                TeamLine(team: game.home, game: game, showScore: showScore)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .trailing, spacing: 4) {
                StatusLabel(game: game)
                if let net = game.networks.first {
                    Text(net).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(game.league.label).font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(width: 92, alignment: .trailing)
        }
        .padding(14)
        .glassCard(cornerRadius: 20)
        .contentShape(Rectangle())
    }
}

// MARK: Mini player

/// Shows above the tab bar while something plays and the full screen player is closed.
struct MiniPlayerBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let channel = model.player.current, !model.showPlayer {
            let player = model.player
            let now = model.nowNext(channel).now
            HStack(spacing: 4) {
                Button {
                    model.showPlayer = true
                } label: {
                    HStack(spacing: 12) {
                        // The live picture keeps going in a small window, like on the TV.
                        PlayerSurface(player: player.avPlayer) { player.attach(layer: $0) }
                            .frame(width: 72, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .allowsHitTesting(false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(player.status.isEmpty ? (now?.title ?? "Now playing") : player.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    player.togglePlay()
                } label: {
                    Image(systemName: player.isPaused || player.failed ? "play.fill" : "pause.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPaused ? "Play" : "Pause")

                Button {
                    model.stopPlayback()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop")
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }
}

extension View {
    func miniPlayerInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
    }
}
