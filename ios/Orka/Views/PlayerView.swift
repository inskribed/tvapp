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
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        let player = model.player
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerSurface(player: player.avPlayer) { player.attach(layer: $0) }
                .ignoresSafeArea()

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }
                .gesture(
                    DragGesture(minimumDistance: 50).onEnded { value in
                        if abs(value.translation.height) > abs(value.translation.width) {
                            player.zap(value.translation.height < 0 ? 1 : -1)
                            poke()
                        }
                    }
                )

            if !player.status.isEmpty && !showControls {
                Text(player.status)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 16)
            }

            if showControls { controls(player) }
        }
        .statusBarHidden(!showControls)
        .preferredColorScheme(.dark)
        .task { poke() }
        .onChange(of: player.current?.id) {
            if player.current == nil { model.showPlayer = false } else { poke() }
        }
        .onDisappear { hideTask?.cancel() }
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(_ player: PlayerModel) -> some View {
        VStack {
            HStack(spacing: 12) {
                roundButton("chevron.down") { model.showPlayer = false }
                if let channel = player.current {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.name).font(.headline).lineLimit(1)
                        Text("\(player.queue.isEmpty ? 0 : player.index + 1) of \(player.queue.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .shadow(radius: 6)
                    Spacer(minLength: 0)
                    roundButton(model.isFavorite(channel) ? "star.fill" : "star") {
                        model.toggleFavorite(channel)
                        poke()
                    }
                }
                if AVPictureInPictureController.isPictureInPictureSupported() {
                    roundButton("pip.enter") { player.togglePictureInPicture() }
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
                    HStack(spacing: 28) {
                        roundButton("backward.fill", size: 52) { player.zap(-1); poke() }
                        roundButton(player.isPaused || player.failed ? "play.fill" : "pause.fill", size: 68) {
                            player.togglePlay()
                            poke()
                        }
                        roundButton("forward.fill", size: 52) { player.zap(1); poke() }
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
                    Text("Swipe up or down to change channel")
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

    private func roundButton(_ icon: String, size: CGFloat = 44, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
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
            if !p.failed && !p.isPaused {
                withAnimation { showControls = false }
            }
        }
    }
}
