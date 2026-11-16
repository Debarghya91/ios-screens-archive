// AudioPlayerService.swift
// Payments Training Hub iOS - Lesson audio playback with automatic failover.
// Streams from the primary audio host, and if the primary fails, switches
// to the backup audio host automatically, resuming from the same position.
// The audio session uses the .playback category so narration plays with
// sound even when the silent switch is on, and autoplay starts as soon as
// the item is ready to play. isPlaying only turns true once the player is
// actually playing.
// No em dashes in any user-facing text.

import Foundation
import AVFoundation
import Combine
import MediaPlayer
import UIKit
import os

/// Posted when access changes in a way that must stop playback
/// everywhere: sign-out and account entitlement clearing. Every
/// live AudioPlayerService stops on it, including players owned
/// by views that are not on screen, so narration never keeps
/// playing after a lock flip or a sign-out.
extension Notification.Name {
    static let pfStopAudioForAccessChange = Notification.Name("pf.audio.stopForAccessChange")
}

/// Plays lesson narration with automatic failover between audio hosts.
final class AudioPlayerService: ObservableObject {
    // MARK: - Published state

    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var playbackRate: Float = 1.0
    @Published private(set) var isMuted = false
    @Published private(set) var isUsingFallback = false
    @Published private(set) var errorMessage: String? = nil

    /// True while the item now playing came from a downloaded file
    /// on this device rather than streaming. The lesson view shows
    /// "Playing the downloaded copy" from this. Cleared on stop and
    /// when playback falls back to streaming.
    @Published private(set) var isPlayingDownloadedCopy = false

    /// Sleep timer, in minutes, nil when off. Fires once and stops playback.
    @Published private(set) var sleepTimerMinutes: Int? = nil

    /// Auto-advance to the next lesson when narration finishes.
    /// Default off. Persisted locally.
    @Published var autoAdvanceEnabled: Bool = false {
        didSet {
            guard !isReloadingPrefs else { return }
            UserDefaults.standard.set(autoAdvanceEnabled, forKey: AccountScopedStorage.currentKey(Keys.autoAdvance))
        }
    }

    /// The position this lesson resumed from, when position persistence
    /// restored a saved position. Nil when playback started from 0.
    /// The lesson view shows "Resumed from MM:SS" from this.
    @Published private(set) var resumedFromPosition: Double? = nil

    /// Sleep timer options offered in the player, in minutes.
    static let sleepTimerOptions: [Int] = [5, 10, 15, 30]

    /// Playback speeds offered by the player, in order.
    static let playbackSpeeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    /// Called exactly once when playback reaches the end of the item.
    /// The lesson view uses it to auto-advance to the next lesson.
    var onFinished: (() -> Void)?

    /// Called from a headphone, lock-screen or car next/previous
    /// command. The lesson view wires these to its next and previous
    /// lesson; nil when no neighbour exists in that direction.
    var onNextLesson: (() -> Void)?
    var onPreviousLesson: (() -> Void)?

    /// Now Playing metadata for the lesson now playing. Set by play()
    /// and refreshed by updateLessonMetadata(title:chapterTitle:)
    /// once the lesson detail has loaded.
    private(set) var currentLessonTitle: String? = nil
    private(set) var currentChapterTitle: String? = nil

    // MARK: - Private state

    private var player: AVPlayer?
    private var currentItem: AVPlayerItem?
    private var statusObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var currentFileName: String?
    private var currentLessonID: String?
    private var failoverAttempted = false
    private var failoverTimer: Timer?
    private var sleepTimer: Timer?
    private var resumePosition: Double = 0
    private var cancellables = Set<AnyCancellable>()
    /// True while the current item has NotificationCenter observers
    /// registered for it. Guards against adding the same observers
    /// twice and makes removal exact (per item, not object:nil).
    private var itemObserversRegistered = false
    /// True once the remote-command targets have been added.
    /// Remote commands are wired once in init and removed in deinit.
    private var remoteCommandsSetup = false
    /// Last Now Playing update, so the 0.5s time observer refreshes
    /// the lock screen at most once a second.
    private var lastNowPlayingUpdate = Date.distantPast

    /// Local persistence keys, as base keys. The stored keys are
    /// namespaced per account through AccountScopedStorage:
    /// playback rate, auto-advance and per-lesson positions are
    /// personal to the learner.
    private enum Keys {
        static let playbackRate = "pf.audio.playbackRate.v1"
        static let autoAdvance = "pf.audio.autoAdvance.v1"
        static let positionPrefix = "pf.audio.position.v1."
    }

    /// True while reloadForCurrentAccount is re-reading prefs, so
    /// the auto-advance observer does not write the loaded value
    /// back into a namespace that may not hold it yet.
    private var isReloadingPrefs = false

    /// The namespace captured when the current playback started.
    /// Positions are written under it, so stopping playback after
    /// an account switch cannot file the position under the new
    /// account. Nil when nothing has been played yet.
    private var positionNamespace: String?

    /// True while a play has been requested but the item is not ready yet.
    /// Playback starts the moment the item reports readyToPlay.
    private var pendingPlay = false
    /// Guards onFinished so it fires exactly once per item.
    private var didFireFinished = false
    /// True if playback was active when an interruption began.
    private var wasPlayingBeforeInterruption = false
    /// Increments on every stop(), so delayed work captured for an
    /// older session can prove it is stale before acting.
    private var playbackGeneration = 0
    /// The playback generation captured when an interruption
    /// began. An interruption that ends after a stop and a fresh
    /// play must not resume the new session.
    private var interruptionGeneration = 0
    /// The instance that last published Now Playing info. The
    /// lock-screen info is shared, and several per-view services
    /// can exist across the navigation stack, so only the owning
    /// instance may clear it.
    private static var nowPlayingOwner: ObjectIdentifier?

    /// Structured audio log, visible in Console and sysdiagnose.
    /// One line per playback transition, with the generation and
    /// the lesson id, so a crash report's breadcrumbs can be
    /// matched against the playback sequence.
    private let audioLog = Logger(subsystem: "PaymentsTrainingHub", category: "Audio")

    private func logAudio(_ event: String, detail: String = "") {
        let message = "gen=\(playbackGeneration) lesson=\(currentLessonID ?? "-") \(event)\(detail.isEmpty ? "" : " \(detail)")"
        audioLog.info("\(message, privacy: .public)")
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, currentTime / duration)
    }

    init() {
        AccountScopedStorage.adoptLegacyKey(Keys.playbackRate)
        AccountScopedStorage.adoptLegacyKey(Keys.autoAdvance)
        AccountScopedStorage.adoptLegacyKeys(withPrefix: Keys.positionPrefix)
        let savedRate = Float(UserDefaults.standard.double(forKey: AccountScopedStorage.currentKey(Keys.playbackRate)))
        if Self.playbackSpeeds.contains(savedRate) {
            playbackRate = savedRate
        }
        autoAdvanceEnabled = UserDefaults.standard.bool(forKey: AccountScopedStorage.currentKey(Keys.autoAdvance))
        setupRemoteCommands()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAccessChange(_:)),
            name: .pfStopAudioForAccessChange,
            object: nil
        )
    }

    // MARK: - Position persistence

    /// The saved playback position for a lesson, in seconds, under
    /// the current account namespace. Zero when the lesson was
    /// never started or was finished.
    static func savedPosition(for lessonID: String) -> Double {
        let saved = UserDefaults.standard.double(forKey: AccountScopedStorage.currentKey(Keys.positionPrefix + lessonID))
        return saved.isFinite && saved > 0 ? saved : 0
    }

    /// The stored key for a lesson's saved position when writing.
    /// Positions are written under the namespace captured when
    /// playback started (see positionNamespace), never under a
    /// namespace the learner switched into mid-lesson.
    private func positionKey(for lessonID: String) -> String {
        AccountScopedStorage.key(Keys.positionPrefix + lessonID, namespace: positionNamespace ?? AccountScopedStorage.currentNamespace)
    }

    /// Re-read playback rate and auto-advance for the current
    /// account namespace. Playback itself is untouched: audio is
    /// content, not account data, and a switch mid-lesson must not
    /// stop the narration. Positions are read per lesson at play()
    /// time, so the next lesson already uses the new namespace.
    /// There is no shared instance (each LessonView owns one), so
    /// AuthService cannot call this for live players; new lesson
    /// views read the current namespace in init.
    func reloadForCurrentAccount() {
        isReloadingPrefs = true
        defer { isReloadingPrefs = false }
        if UserDefaults.standard.object(forKey: AccountScopedStorage.currentKey(Keys.playbackRate)) != nil {
            let savedRate = Float(UserDefaults.standard.double(forKey: AccountScopedStorage.currentKey(Keys.playbackRate)))
            if Self.playbackSpeeds.contains(savedRate) {
                playbackRate = savedRate
            }
        } else {
            playbackRate = 1.0
        }
        autoAdvanceEnabled = UserDefaults.standard.bool(forKey: AccountScopedStorage.currentKey(Keys.autoAdvance))
    }

    /// Save the current position for the lesson now playing, if any.
    /// Called on pause and on stop (lesson close), so reopening the
    /// lesson resumes from the exact saved position. Positions under
    /// 5 seconds are not worth resuming from and are cleared.
    func savePosition() {
        guard let lessonID = currentLessonID else { return }
        if currentTime > 5 {
            UserDefaults.standard.set(currentTime, forKey: positionKey(for: lessonID))
        } else {
            UserDefaults.standard.removeObject(forKey: positionKey(for: lessonID))
        }
    }

    /// Drop the saved position for a lesson, for example when it finishes.
    func clearSavedPosition(for lessonID: String) {
        UserDefaults.standard.removeObject(forKey: positionKey(for: lessonID))
    }

    // MARK: - Audio session

    /// Use the playback category so narration is heard with sound even
    /// when the silent switch is on, and activate the session before any
    /// play attempt. A failure here never blocks playback outright.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            // Without the category the silent switch may mute narration,
            // but playback is still attempted. The failure is logged:
            // a silent session failure used to be undiagnosable.
            logAudio("SESSION_CONFIG_FAILED", detail: error.localizedDescription)
        }
    }

    /// Pause on interruption begin (for example a phone call) and resume
    /// on interruption end if playback was active before it. The
    /// handler hops to the main thread first: notification delivery
    /// has no thread guarantee, and it mutates published state.
    /// An interruption that ends in a newer generation than the one
    /// it began in never resumes: the learner stopped and started
    /// something else in between.
    @objc private func handleInterruption(_ notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.handleInterruption(notification) }
            return
        }
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            interruptionGeneration = playbackGeneration
            wasPlayingBeforeInterruption = isPlaying
            logAudio("INTERRUPTION_BEGAN")
            if isPlaying {
                pause()
            }
        case .ended:
            let wasPlaying = wasPlayingBeforeInterruption
            let generationMatches = interruptionGeneration == playbackGeneration
            wasPlayingBeforeInterruption = false
            logAudio("INTERRUPTION_ENDED")
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume), wasPlaying, generationMatches {
                resume()
            }
        @unknown default:
            break
        }
    }

    /// Pause when the audio route loses its output device, for
    /// example when headphones are unplugged. Without this,
    /// narration keeps playing out loud through the speaker.
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
              reason == .oldDeviceUnavailable,
              let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
              previousRoute.outputs.contains(where: { $0.portType == .headphones || $0.portType == .bluetoothA2DP || $0.portType == .bluetoothLE || $0.portType == .bluetoothHFP }),
              isPlaying else { return }
        DispatchQueue.main.async { [weak self] in self?.pause() }
    }

    /// Stop on an access change (sign-out, entitlement clearing),
    /// even when this service's view is not on screen.
    @objc private func handleAccessChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.stop() }
    }

    // MARK: - Now Playing and remote commands

    /// Refresh the lesson title and chapter used for Now Playing
    /// metadata, for example once the lesson detail has loaded after
    /// playback already started. Updates the lock screen immediately.
    func updateLessonMetadata(title: String?, chapterTitle: String?) {
        if let title, !title.isEmpty { currentLessonTitle = title }
        if let chapterTitle, !chapterTitle.isEmpty { currentChapterTitle = chapterTitle }
        updateNowPlayingInfo()
    }

    /// Publish the lesson title, chapter, artwork, elapsed and total
    /// time and playback rate to the lock screen and Control Centre.
    /// Artwork is the bundled app icon, never a remote fetch that can
    /// fail. Called on play, pause, seek, speed change and at most
    /// once a second while playing.
    func updateNowPlayingInfo() {
        guard player?.currentItem != nil else {
            // The info dictionary is shared across the app, so
            // only the instance that last published may clear it.
            if Self.nowPlayingOwner == ObjectIdentifier(self) {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                Self.nowPlayingOwner = nil
            }
            return
        }
        Self.nowPlayingOwner = ObjectIdentifier(self)
        lastNowPlayingUpdate = Date()
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentLessonTitle ?? "Payments Training Hub lesson",
            MPMediaItemPropertyArtist: "Payments Training Hub",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: playbackRate
        ]
        if let chapter = currentChapterTitle, !chapter.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = chapter
        }
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let icon = UIImage(named: "AppIcon") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: icon.size, requestHandler: { _ in icon })
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Wire the lock-screen, headphone and car controls once. Play,
    /// pause, next and previous lesson, 15s skip, seek to a position
    /// and playback rate. Each handler is a no-op returning
    /// .commandFailed when there is nothing to act on, so a command
    /// never fires twice or on a torn-down player.
    /// Register remote commands with target/action, not closures:
    /// teardown can then remove only this instance's targets.
    /// Closure targets removed with removeTarget(nil) would strip
    /// every other live service's targets too, and several
    /// per-view services can exist across the navigation stack.
    private func setupRemoteCommands() {
        guard !remoteCommandsSetup else { return }
        remoteCommandsSetup = true
        let centre = MPRemoteCommandCenter.shared()
        centre.playCommand.addTarget(self, action: #selector(handleRemotePlay))
        centre.pauseCommand.addTarget(self, action: #selector(handleRemotePause))
        centre.togglePlayPauseCommand.addTarget(self, action: #selector(handleRemoteTogglePlayPause))
        centre.nextTrackCommand.addTarget(self, action: #selector(handleRemoteNextTrack))
        centre.previousTrackCommand.addTarget(self, action: #selector(handleRemotePreviousTrack))
        centre.skipForwardCommand.preferredIntervals = [15]
        centre.skipForwardCommand.addTarget(self, action: #selector(handleRemoteSkipForward(_:)))
        centre.skipBackwardCommand.preferredIntervals = [15]
        centre.skipBackwardCommand.addTarget(self, action: #selector(handleRemoteSkipBackward(_:)))
        centre.changePlaybackPositionCommand.addTarget(self, action: #selector(handleRemoteChangePosition(_:)))
        centre.changePlaybackRateCommand.supportedPlaybackRates = Self.playbackSpeeds.map { NSNumber(value: $0) }
        centre.changePlaybackRateCommand.addTarget(self, action: #selector(handleRemoteChangeRate(_:)))
    }

    @objc private func handleRemotePlay() -> MPRemoteCommandHandlerStatus {
        guard player?.currentItem != nil else { return .commandFailed }
        resume()
        return .success
    }

    @objc private func handleRemotePause() -> MPRemoteCommandHandlerStatus {
        guard isPlaying else { return .commandFailed }
        pause()
        return .success
    }

    @objc private func handleRemoteTogglePlayPause() -> MPRemoteCommandHandlerStatus {
        guard player?.currentItem != nil else { return .commandFailed }
        togglePlayPause()
        return .success
    }

    @objc private func handleRemoteNextTrack() -> MPRemoteCommandHandlerStatus {
        guard let next = onNextLesson else { return .commandFailed }
        next()
        return .success
    }

    @objc private func handleRemotePreviousTrack() -> MPRemoteCommandHandlerStatus {
        guard let previous = onPreviousLesson else { return .commandFailed }
        previous()
        return .success
    }

    @objc private func handleRemoteSkipForward(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard player?.currentItem != nil else { return .commandFailed }
        let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
        seekForward(interval)
        return .success
    }

    @objc private func handleRemoteSkipBackward(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard player?.currentItem != nil else { return .commandFailed }
        let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
        seekBackward(interval)
        return .success
    }

    @objc private func handleRemoteChangePosition(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent,
              player?.currentItem != nil else { return .commandFailed }
        seek(to: positionEvent.positionTime)
        return .success
    }

    @objc private func handleRemoteChangeRate(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard let rateEvent = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
        setSpeed(rateEvent.playbackRate)
        return .success
    }

    /// Remove this instance's remote-command targets only. Called
    /// once from deinit; setupRemoteCommands() guards against
    /// adding them twice.
    private func teardownRemoteCommands() {
        guard remoteCommandsSetup else { return }
        remoteCommandsSetup = false
        let centre = MPRemoteCommandCenter.shared()
        centre.playCommand.removeTarget(self)
        centre.pauseCommand.removeTarget(self)
        centre.togglePlayPauseCommand.removeTarget(self)
        centre.nextTrackCommand.removeTarget(self)
        centre.previousTrackCommand.removeTarget(self)
        centre.skipForwardCommand.removeTarget(self)
        centre.skipBackwardCommand.removeTarget(self)
        centre.changePlaybackPositionCommand.removeTarget(self)
        centre.changePlaybackRateCommand.removeTarget(self)
    }

    // MARK: - Loading

    /// Load and play a lesson audio file, trying the primary host first.
    /// When lessonID is given, playback resumes from the exact saved
    /// position for that lesson, if one was saved. The lesson view
    /// passes the lesson id; callers that do not know it keep the old
    /// behaviour and start from the beginning. Title and chapterTitle
    /// feed the lock-screen Now Playing metadata; the lesson view
    /// refreshes them with updateLessonMetadata once the detail loads.
    /// When a downloaded copy exists for the lesson, it plays from
    /// this device instead of streaming; the remote primary to
    /// fallback failover is unchanged when no download exists. A
    /// downloaded copy can only be found when lessonID is given.
    func play(fileName: String, lessonID: String? = nil, title: String? = nil, chapterTitle: String? = nil) {
        stop()
        currentFileName = fileName
        currentLessonID = lessonID
        positionNamespace = AccountScopedStorage.currentNamespace
        currentLessonTitle = title
        currentChapterTitle = chapterTitle
        failoverAttempted = false
        wasPlayingBeforeInterruption = false
        isUsingFallback = false
        isPlayingDownloadedCopy = false
        errorMessage = nil
        isLoading = true
        resumePosition = 0
        resumedFromPosition = nil
        logAudio("PLAY_REQUESTED", detail: fileName)
        CrashBreadcrumbs.record("audio play \(lessonID ?? fileName)")
        if let lessonID {
            let saved = Self.savedPosition(for: lessonID)
            if saved > 0 {
                resumePosition = saved
                resumedFromPosition = saved
            }
        }
        pendingPlay = true
        configureAudioSession()
        if let lessonID,
           let downloadedURL = LessonDownloadStore.shared.downloadedAudioURL(for: lessonID, fileName: fileName) {
            isPlayingDownloadedCopy = true
            startPlayback(url: downloadedURL)
        } else if let url = ContentService.primaryAudioURL(fileName: fileName) {
            startPlayback(url: url)
        } else {
            // The file name cannot form a valid audio URL: a load
            // failure, shown like any other, never a crash.
            pendingPlay = false
            errorMessage = "Audio could not be loaded from either audio host. Check your connection and try again, or read the transcript below."
            isPlaying = false
            isLoading = false
        }
    }

    private func startPlayback(url: URL) {
        // Drop every observer belonging to the previous item before
        // the new one is built, so the failover path never leaves
        // stale observers behind and no observer is added twice.
        removeItemObservers()

        let item = AVPlayerItem(url: url)
        currentItem = item
        let player = AVPlayer(playerItem: item)
        self.player = player
        player.isMuted = isMuted
        didFireFinished = false
        isLoading = true
        // Delayed work below (failover timer, KVO) captures this
        // generation and refuses to act when it has moved on, so a
        // stop and a fresh play can never be undone by stale work
        // from the session that came before.
        let generation = playbackGeneration

        // Fail over if no playable data arrives within 8 seconds.
        failoverTimer?.invalidate()
        failoverTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            guard let self, generation == self.playbackGeneration, self.currentItem === item else { return }
            if self.duration <= 0 && self.currentTime <= 0 {
                self.tryFailover()
            }
        }

        // Observe playback state. Registered once per item and removed
        // by removeItemObservers() before the next item or on stop.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailed(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFinished(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
        itemObserversRegistered = true

        // Do not claim to be playing until the item is actually ready.
        // Playback starts from here, never from a bare player.play() call.
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                guard generation == self.playbackGeneration else { return }
                self.handleItemStatus(observedItem)
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            // NaN/Infinity from a not-yet-loaded item would poison
            // the seek slider and the position display: ignore it.
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            self.currentTime = seconds
            if let itemDuration = self.player?.currentItem?.duration, itemDuration.isNumeric {
                let durationSeconds = itemDuration.seconds
                if durationSeconds.isFinite { self.duration = durationSeconds }
            }
            if self.duration > 0 {
                self.failoverTimer?.invalidate()
            }
            // Lock-screen elapsed time, at most once a second.
            if Date().timeIntervalSince(self.lastNowPlayingUpdate) >= 1 {
                self.updateNowPlayingInfo()
            }
        }
    }

    /// Remove the current item's observers and invalidate its status
    /// observation and time observer. Safe to call when nothing is
    /// registered. This is the single teardown path for item
    /// observers, used by startPlayback (failover), stop() and deinit.
    private func removeItemObservers() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        if itemObserversRegistered, let item = currentItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: item)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
            itemObserversRegistered = false
        }
        currentItem = nil
    }

    /// Called whenever the item status changes. Starts playback the moment
    /// the item is ready, and fails over if the item cannot be played.
    private func handleItemStatus(_ item: AVPlayerItem) {
        // A stale item's status change (dispatched before a stop)
        // must never fail over the session that replaced it.
        guard item === currentItem else { return }
        switch item.status {
        case .readyToPlay:
            let itemDuration = item.duration
            if itemDuration.isNumeric {
                let seconds = itemDuration.seconds
                if seconds.isFinite { duration = seconds }
            }
            if pendingPlay {
                beginPlayback()
            }
        case .failed:
            tryFailover()
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    /// Start the player now that the item is ready. A failover resume
    /// position is sought first, then playback starts from that position.
    private func beginPlayback() {
        guard pendingPlay, let player else { return }
        pendingPlay = false
        let generation = playbackGeneration
        let start: () -> Void = { [weak self] in
            guard let self, let player = self.player, generation == self.playbackGeneration else { return }
            player.rate = self.playbackRate
            self.isPlaying = true
            self.isLoading = false
            self.updateNowPlayingInfo()
            self.logAudio("PLAY_STARTED")
        }
        if resumePosition > 0 {
            let position = resumePosition
            resumePosition = 0
            let upper = duration > 0 ? duration : max(0, position)
            let clamped = min(max(0, position), upper)
            player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600)) { finished in
                DispatchQueue.main.async {
                    guard finished else { return }
                    start()
                }
            }
        } else {
            start()
        }
    }

    // MARK: - Failover

    @objc private func playerItemFailed(_ notification: Notification) {
        // Notification delivery has no thread guarantee, and the
        // item may belong to a session that has been replaced.
        guard let item = notification.object as? AVPlayerItem, item === currentItem else { return }
        DispatchQueue.main.async { [weak self] in self?.tryFailover() }
    }

    private func tryFailover() {
        guard currentItem != nil else { return }
        guard let fileName = currentFileName, !failoverAttempted else {
            pendingPlay = false
            errorMessage = "Audio could not be loaded from either audio host. Check your connection and try again, or read the transcript below."
            isPlaying = false
            isLoading = false
            logAudio("FAILOVER_EXHAUSTED")
            if let lessonID = currentLessonID {
                AnalyticsService.shared.recordAudioPlaybackFailed(lessonID: lessonID, failureCategory: "bothHostsFailed")
            }
            return
        }
        if isPlayingDownloadedCopy {
            // The downloaded file could not be played: fall back to
            // streaming from the primary host, with the full
            // primary to fallback chain still ahead of it. When no
            // valid primary URL can be built, the load is exhausted
            // exactly as if both hosts had failed.
            isPlayingDownloadedCopy = false
            resumePosition = currentTime
            logAudio("FAILOVER", detail: "downloaded to primary")
            if let url = ContentService.primaryAudioURL(fileName: fileName) {
                startPlayback(url: url)
                return
            }
            pendingPlay = false
            errorMessage = "Audio could not be loaded from either audio host. Check your connection and try again, or read the transcript below."
            isPlaying = false
            isLoading = false
            logAudio("FAILOVER_EXHAUSTED")
            if let lessonID = currentLessonID {
                AnalyticsService.shared.recordAudioPlaybackFailed(lessonID: lessonID, failureCategory: "bothHostsFailed")
            }
            return
        }
        failoverAttempted = true
        isUsingFallback = true
        resumePosition = currentTime
        logAudio("FAILOVER", detail: "primary to fallback")
        guard let fallbackURL = ContentService.fallbackAudioURL(fileName: fileName) else {
            pendingPlay = false
            errorMessage = "Audio could not be loaded from either audio host. Check your connection and try again, or read the transcript below."
            isPlaying = false
            isLoading = false
            logAudio("FAILOVER_EXHAUSTED")
            if let lessonID = currentLessonID {
                AnalyticsService.shared.recordAudioPlaybackFailed(lessonID: lessonID, failureCategory: "bothHostsFailed")
            }
            return
        }
        startPlayback(url: fallbackURL)
    }

    // MARK: - Controls

    func pause() {
        savePosition()
        pendingPlay = false
        player?.pause()
        isPlaying = false
        isLoading = false
        logAudio("PAUSE", detail: "at \(Int(currentTime))s")
        CrashBreadcrumbs.record("audio pause \(currentLessonID ?? "") at \(Int(currentTime))s")
        updateNowPlayingInfo()
    }

    func resume() {
        guard player?.currentItem != nil else { return }
        configureAudioSession()
        // Replaying after the item ended restarts from the beginning.
        if duration > 0 && currentTime >= duration - 0.5 {
            seek(to: 0)
        }
        pendingPlay = true
        logAudio("RESUME")
        if player?.currentItem?.status == .readyToPlay {
            beginPlayback()
        } else {
            isLoading = true
        }
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func seek(to seconds: Double) {
        // A non-finite or negative seek is ignored: with no known
        // duration the old upper bound could itself be negative,
        // and a negative CMTime is meaningless to the player.
        guard seconds.isFinite else { return }
        let upper = duration > 0 ? duration : max(0, seconds)
        let clamped = min(max(0, seconds), upper)
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player?.seek(to: time)
        currentTime = clamped
        updateNowPlayingInfo()
    }

    func seekForward(_ seconds: Double = 15) {
        seek(to: currentTime + seconds)
    }

    func seekBackward(_ seconds: Double = 15) {
        seek(to: currentTime - seconds)
    }

    /// Set a playback speed and persist it, so it survives relaunch.
    func setSpeed(_ rate: Float) {
        guard Self.playbackSpeeds.contains(rate) else { return }
        playbackRate = rate
        UserDefaults.standard.set(rate, forKey: AccountScopedStorage.currentKey(Keys.playbackRate))
        if isPlaying { player?.rate = rate }
        updateNowPlayingInfo()
    }

    /// Cycle through playback speeds: 0.75x, 1x, 1.25x, 1.5x, 2x,
    /// then back to 0.75x. The chosen speed persists.
    func cycleSpeed() {
        let speeds = Self.playbackSpeeds
        let currentIndex = speeds.firstIndex(of: playbackRate) ?? 1
        setSpeed(speeds[(currentIndex + 1) % speeds.count])
    }

    /// Short label for the current speed, for the player button.
    /// Matches the mockup's player bar: "1.0x", "1.5x", "2.0x".
    var speedLabel: String {
        switch playbackRate {
        case 0.75: return "0.75x"
        case 1.25: return "1.25x"
        case 1.5: return "1.5x"
        case 2.0: return "2.0x"
        default: return "1.0x"
        }
    }

    // MARK: - Sleep timer

    /// Short label for the sleep timer, for the player button.
    var sleepTimerLabel: String {
        guard let minutes = sleepTimerMinutes else { return "Off" }
        return "\(minutes)m"
    }

    /// Set the sleep timer in minutes, or nil to turn it off. When it
    /// fires, playback stops. The timer keeps running across lesson
    /// changes until it fires or is turned off.
    func setSleepTimer(minutes: Int?) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerMinutes = minutes
        guard let minutes else { return }
        sleepTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.sleepTimerMinutes = nil
            self.sleepTimer = nil
            self.pause()
        }
    }

    /// Cycle the sleep timer: Off, 5, 10, 15, 30 minutes, then Off.
    func cycleSleepTimer() {
        let options = Self.sleepTimerOptions
        guard let current = sleepTimerMinutes,
              let index = options.firstIndex(of: current) else {
            setSleepTimer(minutes: options.first)
            return
        }
        let next = index + 1 < options.count ? options[index + 1] : nil
        setSleepTimer(minutes: next)
    }

    /// Set the auto-advance toggle and persist it. Default off.
    func setAutoAdvance(_ enabled: Bool) {
        autoAdvanceEnabled = enabled
    }

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    func stop() {
        // The generation moves first: every delayed callback
        // captured for the session being torn down becomes stale
        // before any other state changes.
        playbackGeneration += 1
        logAudio("STOP")
        savePosition()
        failoverTimer?.invalidate()
        failoverTimer = nil
        // The sleep timer is deliberately NOT invalidated here: it
        // keeps running across lesson changes until it fires or is
        // turned off. It is invalidated in deinit.
        removeItemObservers()
        player?.pause()
        player = nil
        pendingPlay = false
        didFireFinished = false
        resumePosition = 0
        resumedFromPosition = nil
        positionNamespace = nil
        currentLessonID = nil
        currentLessonTitle = nil
        currentChapterTitle = nil
        currentFileName = nil
        failoverAttempted = false
        wasPlayingBeforeInterruption = false
        isUsingFallback = false
        isPlaying = false
        isLoading = false
        isPlayingDownloadedCopy = false
        currentTime = 0
        duration = 0
        errorMessage = nil
        if Self.nowPlayingOwner == ObjectIdentifier(self) {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            Self.nowPlayingOwner = nil
        }
    }

    @objc private func playerItemFinished(_ notification: Notification) {
        // Notification delivery has no thread guarantee, and the
        // item may belong to a session that has been replaced.
        // The generation is captured so the delayed finish
        // callback never fires for a session that has moved on.
        guard let item = notification.object as? AVPlayerItem, item === currentItem else { return }
        let generation = playbackGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.playbackGeneration, !self.didFireFinished else { return }
            self.didFireFinished = true
            self.pendingPlay = false
            self.isPlaying = false
            if let lessonID = self.currentLessonID {
                self.clearSavedPosition(for: lessonID)
                // Narration played to the end: record the real listening
                // time (only a finished listen counts; partial listens
                // are not recorded, so learning hours are never estimated).
                if self.currentTime > 0 {
                    ProgressStore.shared.recordAudioListened(lessonID: lessonID, seconds: Int(self.currentTime))
                }
            }
            self.logAudio("FINISHED")
            self.updateNowPlayingInfo()
            self.onFinished?()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: .pfStopAudioForAccessChange, object: nil)
        teardownRemoteCommands()
        sleepTimer?.invalidate()
        sleepTimer = nil
        failoverTimer?.invalidate()
        failoverTimer = nil
        stop()
    }
}

// MARK: - Helpers

extension CMTime {
    var isNumeric: Bool {
        flags.contains(.valid) && !flags.contains(.indefinite) && !flags.contains(.negativeInfinity) && !flags.contains(.positiveInfinity)
    }
}
