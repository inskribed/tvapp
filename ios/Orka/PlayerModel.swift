import AVFoundation
import AVKit
import Combine
import Observation
import OrkaCore

/// Owns the one AVPlayer: queue, channel up/down, reconnecting, picture in picture.
/// It keeps playing (audio) when the full screen player is closed, so the mini player can show it.
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
    @ObservationIgnored private var zapTask: Task<Void, Never>?
    @ObservationIgnored private var retries = 0
    private let maxRetries = 6

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
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
        retryTask?.cancel()
        zapTask?.cancel()
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
        isPaused.toggle()
        if isPaused { avPlayer.pause() } else { avPlayer.play() }
    }

    func stop() {
        zapTask?.cancel()
        retryTask?.cancel()
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
    }

    // MARK: Picture in picture

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
        retryTask?.cancel()
        failed = false
        retries = 0
        isPaused = false
        reload()
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
        case .readyToPlay: status = ""
        default: break
        }
    }

    private func timeControlChanged(_ value: AVPlayer.TimeControlStatus) {
        switch value {
        case .playing:
            status = ""
            retries = 0
        case .waitingToPlayAtSpecifiedRate:
            if !failed && current != nil { status = retries > 0 ? "Reconnecting…" : "Loading…" }
        default:
            break
        }
    }

    private func connectionDropped() {
        guard current != nil, !failed else { return }
        if retries < maxRetries {
            retries += 1
            let attempt = retries
            status = "Reconnecting… (\(attempt))"
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Double(attempt)))
                guard !Task.isCancelled else { return }
                self?.reload()
            }
        } else {
            failed = true
            status = "This channel isn't responding. Tap play to try again."
        }
    }
}
