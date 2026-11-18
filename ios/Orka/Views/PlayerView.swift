import UIKit
import AVFoundation
import AVKit
import SwiftUI
import OrkaCore

/// Plain video surface backed by an AVPlayerLayer (needed for picture in picture).
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    /// Called each time this surface is actually put on screen (hidden tabs keep their copy off screen).
    var onWindow: ((AVPlayerLayer) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onWindow?(playerLayer) }
    }
}

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let onLayer: (AVPlayerLayer) -> Void

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.onWindow = onLayer
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}
}

/// Full screen player. Tap for controls, swipe up or down to change channel.
struct PlayerView: View {
    @Environment(AppModel.self) private var model
    @State private var showControls = true
    @State private var showInfo = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        let player = model.player
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerSurface(player: player.avPlayer) { player.attach(layer: $0) }
                .ignoresSafeArea()

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if showInfo { withAnimation(.snappy) { showInfo = false } } else { toggleControls() }
                }
                .gesture(
                    DragGesture(minimumDistance: 40).onEnded { value in
                        guard abs(value.translation.height) > abs(value.translation.width) else { return }
                        if value.translation.height < 0 {
                            // Swipe up: stream information.
                            withAnimation(.snappy) { showInfo = true }
                            hideTask?.cancel()
                        } else if showInfo {
                            withAnimation(.snappy) { showInfo = false }
                        } else {
                            // Swipe down: keep watching in picture in picture.
                            goToPictureInPicture()
                        }
                    }
                )

            if !player.status.isEmpty && !showControls && !showInfo {
                Text(player.status)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 16)
            }

            if showControls && !showInfo { controls(player) }

            if showInfo, let channel = player.current {
                StreamInfoPanel(channel: channel) {
                    withAnimation(.snappy) { showInfo = false }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .statusBarHidden(!showControls && !showInfo)
        .preferredColorScheme(.dark)
        .task { poke() }
        .onChange(of: player.current?.id) {
            if player.current == nil { model.showPlayer = false } else { poke() }
        }
        .onDisappear { hideTask?.cancel() }
    }

    /// Hands the video to picture in picture (the full screen player closes when it starts).
    /// If the phone can't do that right now, it falls back to the mini player.
    private func goToPictureInPicture() {
        if !model.player.startPictureInPicture() {
            model.showPlayer = false
        }
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(_ player: PlayerModel) -> some View {
        VStack {
            HStack(spacing: 12) {
                roundButton("chevron.down", label: "Close") { model.showPlayer = false }
                if let channel = player.current {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.name).font(.headline).lineLimit(1)
                        Text("\(player.queue.isEmpty ? 0 : player.index + 1) of \(player.queue.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .shadow(radius: 6)
                    Spacer(minLength: 0)
                    roundButton(model.isFavorite(channel) ? "star.fill" : "star", label: "Favorite") {
                        model.toggleFavorite(channel)
                        poke()
                    }
                }
                if AVPictureInPictureController.isPictureInPictureSupported() {
                    roundButton("pip.enter", label: "Picture in picture") { goToPictureInPicture() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            if let channel = player.current {
                let nn = model.nowNext(channel)
                VStack(spacing: 14) {
                    if !player.status.isEmpty {
                        Text(player.status)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(player.failed ? .red : .white)
                    }
                    // Channel down · back 15s · play/pause · ahead 15s · channel up
                    HStack(spacing: 14) {
                        channelButton(up: false) { player.zap(-1); poke() }
                        roundButton("gobackward.15", size: 50, label: "Back 15 seconds") { player.seek(by: -15); poke() }
                        roundButton(player.isPaused || player.failed ? "play.fill" : "pause.fill", size: 66,
                                    label: player.isPaused ? "Play" : "Pause") {
                            player.togglePlay()
                            poke()
                        }
                        roundButton("goforward.15", size: 50, label: "Ahead 15 seconds") { player.seek(by: 15); poke() }
                        channelButton(up: true) { player.zap(1); poke() }
                    }
                    if let now = nn.now {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(now.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            ProgressBar(value: now.progress(at: Date()))
                            Text(nextLine(now, nn.next)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: 20)
                    }
                    Text("Swipe up for info  ·  Swipe down for picture in picture")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .transition(.opacity)
    }

    private func nextLine(_ now: Program, _ next: Program?) -> String {
        var parts = ["until " + now.end.formatted(date: .omitted, time: .shortened)]
        if let next { parts.append("Next: " + next.title) }
        return parts.joined(separator: "  ·  ")
    }

    private func roundButton(_ icon: String, size: CGFloat = 44, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }

    /// Channel up/down: a chevron with a small "CH" so it reads differently from the seek buttons.
    private func channelButton(up: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                if up { Image(systemName: "chevron.up").font(.system(size: 15, weight: .bold)) }
                Text("CH").font(.system(size: 10, weight: .heavy))
                if !up { Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold)) }
            }
            .frame(width: 44, height: 50)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel(up ? "Next channel" : "Previous channel")
    }

    private func toggleControls() {
        if showControls {
            withAnimation { showControls = false }
        } else {
            poke()
        }
    }

    /// Shows the controls and hides them again after a few seconds.
    private func poke() {
        withAnimation { showControls = true }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if Task.isCancelled { return }
            let p = model.player
            if !p.failed && !p.isPaused && !showInfo {
                withAnimation { showControls = false }
            }
        }
    }
}

/// Swipe up in the player: what's on, what's next, and details about the stream itself.
private struct StreamInfoPanel: View {
    @Environment(AppModel.self) private var model
    let channel: Channel
    let onClose: () -> Void

    var body: some View {
        // Refreshes every couple of seconds so the picture size and bitrate stay current.
        TimelineView(.periodic(from: .now, by: 2)) { context in
            let nn = model.nowNext(channel, at: context.date)
            let player = model.player
            VStack(alignment: .leading, spacing: 14) {
                Capsule().fill(.white.opacity(0.35)).frame(width: 40, height: 5)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 12) {
                    ChannelLogo(channel: channel, width: 64, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.name).font(.headline).lineLimit(2)
                        Text(model.groupName(channel.categoryId)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if model.isFavorite(channel) {
                        Image(systemName: "star.fill").foregroundStyle(Brand.star)
                    }
                }
                if let now = nn.now {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOW").font(.caption2.weight(.heavy)).foregroundStyle(model.highlight)
                        Text(now.title).font(.title3.weight(.semibold))
                        Text(timeRange(now) + "  ·  \(minutesLeft(now, at: context.date)) min left")
                            .font(.footnote).foregroundStyle(.secondary)
                        ProgressBar(value: now.progress(at: context.date))
                        if let summary = now.summary {
                            Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(4)
                        }
                    }
                } else {
                    Text(channel.epgId?.isEmpty == false ? "No guide info right now" : "No guide info for this channel")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let next = nn.next {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEXT").font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
                        Text(next.title).font(.subheadline.weight(.medium)).lineLimit(1)
                        Text(timeRange(next)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider().overlay(.white.opacity(0.15))
                HStack {
                    Label(player.status.isEmpty ? "Playing" : player.status,
                          systemImage: player.failed ? "exclamationmark.triangle" : "dot.radiowaves.left.and.right")
                    Spacer()
                    if let details = player.streamDetails() { Text(details) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(20)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .onTapGesture(perform: onClose)
        }
    }

    private func timeRange(_ p: Program) -> String {
        p.start.formatted(date: .omitted, time: .shortened) + " – " + p.end.formatted(date: .omitted, time: .shortened)
    }

    private func minutesLeft(_ p: Program, at date: Date) -> Int {
        max(1, Int(p.end.timeIntervalSince(date) / 60) + 1)
    }
}
