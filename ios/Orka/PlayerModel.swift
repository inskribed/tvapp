import AVFoundation
import AVKit
import Combine
import MediaPlayer
import Observation
import OrkaCore

/// Owns the one AVPlayer: queue, channel up/down, reconnecting, picture in picture,
/// lock screen controls. It keeps playing when the full screen player is closed, so the
/// mini player can keep showing it.
@MainActor
@Observable
final class PlayerModel {
    private(set) var queue: [Channel] = []
    private(set) var index = 0
    private(set) var isPaused = false
    private(set) var status = ""
    private(set) var failed = false

    var current: Channel? { queue.indices.contains(index) ? queue[index] : nil }

    @ObservationIgnored let avPlayer = AVPlayer()
    @ObservationIgnored var urlProvider: (@MainActor (Channel) -> URL?)?
    @ObservationIgnored var onTuned: (@MainActor (Channel) -> Void)?

    @ObservationIgnored private var pip: AVPictureInPictureController?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var itemCancellable: AnyCancellable?
    @ObservationIgnored private var endCancellable: AnyCancellable?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryPending = false
    @ObservationIgnored private var stallTask: Task<Void, Never>?
    @ObservationIgnored private var zapTask: Task<Void, Never>?
    @ObservationIgnored private var remoteCommandsReady = false
    @ObservationIgnored private var retries = 0
    private let maxRetries = 6
    /// A live stream that has been "waiting" this long without an error is treated as dropped.
    private let stallTimeout: Duration = .seconds(15)

    init() {
        avPlayer.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                Task { @MainActor in self?.timeControlChanged(value) }
            }
            .store(in: &cancellables)
    }

    // MARK: Control

    func start(queue: [Channel], index: Int) {
        zapTask?.cancel()
        activateAudio()
        self.queue = queue
        self.index = index
        load()
        if let c = current { onTuned?(c) }
    }

    /// Channel up/down. A short delay lets you flick through several channels without starting each stream.
    func zap(_ delta: Int) {
        guard !queue.isEmpty else { return }
        index = ((index + delta) % queue.count + queue.count) % queue.count
        status = "Loading…"
        failed = false
        cancelRetry()
        zapTask?.cancel()
        updateNowPlaying()
        zapTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.load()
            if let c = self.current { self.onTuned?(c) }
        }
    }

    func togglePlay() {
        if failed {
            load()
            return
        }
        setPaused(!isPaused)
    }

    func setPaused(_ paused: Bool) {
        guard current != nil else { return }
        if failed && !paused {
            load()
            return
        }
        isPaused = paused
        if paused {
            stallTask?.cancel()
            avPlayer.pause()
        } else {
            avPlayer.play()
        }
        updateNowPlaying()
    }

    func stop() {
        zapTask?.cancel()
        cancelRetry()
        stallTask?.cancel()
        itemCancellable = nil
        endCancellable = nil
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        queue = []
        index = 0
        status = ""
        failed = false
        isPaused = false
        retries = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        // Hand the audio back so music or podcasts can resume.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Audio session and lock screen

    /// Claimed only when something starts playing, so opening Orka never stops other apps' audio.
    private func activateAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
        setUpRemoteCommands()
    }

    private func setUpRemoteCommands() {
        guard !remoteCommandsReady else { return }
        remoteCommandsReady = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.setPaused(false) }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.setPaused(true) }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        // Next/previous on the lock screen or headphones change channel.
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.zap(1) }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.zap(-1) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let c = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: c.name,
            MPMediaItemPropertyArtist: "Orka",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0,
        ]
    }

    // MARK: Picture in picture

    /// Called by whichever video surface is on screen (full screen player or the mini player),
    /// so going to the home screen while something plays continues in picture in picture.
    func attach(layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let controller = AVPictureInPictureController(playerLayer: layer)
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        pip = controller
    }

    func togglePictureInPicture() {
        guard let pip else { return }
        if pip.isPictureInPictureActive { pip.stopPictureInPicture() } else { pip.startPictureInPicture() }
    }

    // MARK: Loading and reconnecting

    private func load() {
        cancelRetry()
        failed = false
        retries = 0
        isPaused = false
        reload()
        updateNowPlaying()
    }

    private func reload() {
        guard let channel = current, let url = urlProvider?(channel) else {
            failed = true
            status = "This channel's playlist is missing."
            return
        }
        let item = AVPlayerItem(url: url)
        observe(item)
        avPlayer.replaceCurrentItem(with: item)
        if !isPaused { avPlayer.play() }
        if retries == 0 { status = "Loading…" }
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
        retryPending = false
    }

    private func observe(_ item: AVPlayerItem) {
        itemCancellable = item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                Task { @MainActor in self?.itemStatusChanged(value, item: item) }
            }
        endCancellable = NotificationCenter.default
            .publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            .merge(with: NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item))
            .sink { [weak self] _ in
                // Live streams shouldn't end; treat it as a dropped connection.
                Task { @MainActor in self?.connectionDropped() }
            }
    }

    private func itemStatusChanged(_ value: AVPlayerItem.Status, item: AVPlayerItem) {
        guard item === avPlayer.currentItem else { return }
        switch value {
        case .failed: connectionDropped()
        case .readyToPlay: if !retryPending { status = "" }
        default: break
        }
    }

    private func timeControlChanged(_ value: AVPlayer.TimeControlStatus) {
        switch value {
        case .playing:
            stallTask?.cancel()
            status = ""
            retries = 0
        case .waitingToPlayAtSpecifiedRate:
            if !failed && current != nil {
                if !retryPending { status = retries > 0 ? "Reconnecting…" : "Loading…" }
                watchForStall()
            }
        case .paused:
            stallTask?.cancel()
        @unknown default:
            break
        }
    }

    /// AVPlayer sometimes waits on a dead live stream forever without reporting an error.
    private func watchForStall() {
        stallTask?.cancel()
        let timeout = stallTimeout
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self else { return }
            if self.avPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate && !self.isPaused {
                self.connectionDropped()
            }
        }
    }

    private func connectionDropped() {
        // One failure often arrives twice (item failed + failed-to-end notice); count it once.
        guard current != nil, !failed, !retryPending else { return }
        stallTask?.cancel()
        if retries < maxRetries {
            retries += 1
            retryPending = true
            let attempt = retries
            status = "Reconnecting… (\(attempt))"
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Double(attempt)))
                guard !Task.isCancelled, let self else { return }
                self.retryPending = false
                self.reload()
            }
        } else {
            failed = true
            status = "This channel isn't responding. Tap play to try again."
            updateNowPlaying()
        }
    }
}
