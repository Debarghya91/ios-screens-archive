// AudioPlayerService.swift
// PaymentForge iOS - Lesson audio playback with automatic failover.
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

    /// Sleep timer, in minutes, nil when off. Fires once and stops playback.
    @Published private(set) var sleepTimerMinutes: Int? = nil

    /// Auto-advance to the next lesson when narration finishes.
    /// Default off. Persisted locally.
    @Published var autoAdvanceEnabled: Bool = false {
        didSet { UserDefaults.standard.set(autoAdvanceEnabled, forKey: Keys.autoAdvance) }
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

    /// Local persistence keys. Guest only, UserDefaults, no account.
    private enum Keys {
        static let playbackRate = "pf.audio.playbackRate.v1"
        static let autoAdvance = "pf.audio.autoAdvance.v1"
        static let positionPrefix = "pf.audio.position.v1."
    }

    /// True while a play has been requested but the item is not ready yet.
    /// Playback starts the moment the item reports readyToPlay.
    private var pendingPlay = false
    /// Guards onFinished so it fires exactly once per item.
    private var didFireFinished = false
    /// True if playback was active when an interruption began.
    private var wasPlayingBeforeInterruption = false

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, currentTime / duration)
    }

    init() {
        let savedRate = Float(UserDefaults.standard.double(forKey: Keys.playbackRate))
        if Self.playbackSpeeds.contains(savedRate) {
            playbackRate = savedRate
        }
        autoAdvanceEnabled = UserDefaults.standard.bool(forKey: Keys.autoAdvance)
        setupRemoteCommands()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    // MARK: - Position persistence

    /// The saved playback position for a lesson, in seconds. Zero
    /// when the lesson was never started or was finished.
    static func savedPosition(for lessonID: String) -> Double {
        let saved = UserDefaults.standard.double(forKey: Keys.positionPrefix + lessonID)
        return saved.isFinite && saved > 0 ? saved : 0
    }

    /// Save the current position for the lesson now playing, if any.
    /// Called on pause and on stop (lesson close), so reopening the
    /// lesson resumes from the exact saved position. Positions under
    /// 5 seconds are not worth resuming from and are cleared.
    func savePosition() {
        guard let lessonID = currentLessonID else { return }
        if currentTime > 5 {
            UserDefaults.standard.set(currentTime, forKey: Keys.positionPrefix + lessonID)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.positionPrefix + lessonID)
        }
    }

    /// Drop the saved position for a lesson, for example when it finishes.
    func clearSavedPosition(for lessonID: String) {
        UserDefaults.standard.removeObject(forKey: Keys.positionPrefix + lessonID)
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
            // but playback is still attempted.
        }
    }

    /// Pause on interruption begin (for example a phone call) and resume
    /// on interruption end if playback was active before it.
    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying {
                pause()
            }
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) && wasPlayingBeforeInterruption {
                wasPlayingBeforeInterruption = false
                resume()
            }
        @unknown default:
            break
        }
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
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
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
    private func setupRemoteCommands() {
        guard !remoteCommandsSetup else { return }
        remoteCommandsSetup = true
        let centre = MPRemoteCommandCenter.shared()
        centre.playCommand.addTarget { [weak self] _ in
            guard let self, self.player?.currentItem != nil else { return .commandFailed }
            self.resume()
            return .success
        }
        centre.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.isPlaying else { return .commandFailed }
            self.pause()
            return .success
        }
        centre.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.player?.currentItem != nil else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }
        centre.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, let next = self.onNextLesson else { return .commandFailed }
            next()
            return .success
        }
        centre.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, let previous = self.onPreviousLesson else { return .commandFailed }
            previous()
            return .success
        }
        centre.skipForwardCommand.preferredIntervals = [15]
        centre.skipForwardCommand.addTarget { [weak self] event in
            guard let self, self.player?.currentItem != nil else { return .commandFailed }
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            self.seekForward(interval)
            return .success
        }
        centre.skipBackwardCommand.preferredIntervals = [15]
        centre.skipBackwardCommand.addTarget { [weak self] event in
            guard let self, self.player?.currentItem != nil else { return .commandFailed }
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            self.seekBackward(interval)
            return .success
        }
        centre.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let positionEvent = event as? MPChangePlaybackPositionCommandEvent,
                  self.player?.currentItem != nil else { return .commandFailed }
            self.seek(to: positionEvent.positionTime)
            return .success
        }
        centre.changePlaybackRateCommand.supportedPlaybackRates = Self.playbackSpeeds.map { NSNumber(value: $0) }
        centre.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let self, let rateEvent = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            self.setSpeed(rateEvent.playbackRate)
            return .success
        }
    }

    /// Remove every remote-command target. Called once from deinit;
    /// setupRemoteCommands() guards against adding them twice.
    private func teardownRemoteCommands() {
        guard remoteCommandsSetup else { return }
        remoteCommandsSetup = false
        let centre = MPRemoteCommandCenter.shared()
        centre.playCommand.removeTarget(nil)
        centre.pauseCommand.removeTarget(nil)
        centre.togglePlayPauseCommand.removeTarget(nil)
        centre.nextTrackCommand.removeTarget(nil)
        centre.previousTrackCommand.removeTarget(nil)
        centre.skipForwardCommand.removeTarget(nil)
        centre.skipBackwardCommand.removeTarget(nil)
        centre.changePlaybackPositionCommand.removeTarget(nil)
        centre.changePlaybackRateCommand.removeTarget(nil)
    }

    // MARK: - Loading

    /// Load and play a lesson audio file, trying the primary host first.
    /// When lessonID is given, playback resumes from the exact saved
    /// position for that lesson, if one was saved. The lesson view
    /// passes the lesson id; callers that do not know it keep the old
    /// behaviour and start from the beginning. Title and chapterTitle
    /// feed the lock-screen Now Playing metadata; the lesson view
    /// refreshes them with updateLessonMetadata once the detail loads.
    func play(fileName: String, lessonID: String? = nil, title: String? = nil, chapterTitle: String? = nil) {
        stop()
        currentFileName = fileName
        currentLessonID = lessonID
        currentLessonTitle = title
        currentChapterTitle = chapterTitle
        failoverAttempted = false
        isUsingFallback = false
        errorMessage = nil
        isLoading = true
        resumePosition = 0
        resumedFromPosition = nil
        if let lessonID {
            let saved = Self.savedPosition(for: lessonID)
            if saved > 5 {
                resumePosition = saved
                resumedFromPosition = saved
            }
        }
        pendingPlay = true
        configureAudioSession()
        startPlayback(url: ContentService.primaryAudioURL(fileName: fileName))
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

        // Fail over if no playable data arrives within 8 seconds.
        failoverTimer?.invalidate()
        failoverTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            guard let self else { return }
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
                self.handleItemStatus(observedItem)
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds
            if let itemDuration = self.player?.currentItem?.duration, itemDuration.isNumeric {
                self.duration = itemDuration.seconds
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
        switch item.status {
        case .readyToPlay:
            let itemDuration = item.duration
            if itemDuration.isNumeric {
                duration = itemDuration.seconds
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
        let start: () -> Void = { [weak self] in
            guard let self, let player = self.player else { return }
            player.rate = self.playbackRate
            self.isPlaying = true
            self.isLoading = false
            self.updateNowPlayingInfo()
        }
        if resumePosition > 0 {
            let position = resumePosition
            resumePosition = 0
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) { _ in
                DispatchQueue.main.async { start() }
            }
        } else {
            start()
        }
    }

    // MARK: - Failover

    @objc private func playerItemFailed(_ notification: Notification) {
        tryFailover()
    }

    private func tryFailover() {
        guard let fileName = currentFileName, !failoverAttempted else {
            pendingPlay = false
            errorMessage = "Audio could not be loaded from either audio host. Check your connection and try again, or read the transcript below."
            isPlaying = false
            isLoading = false
            return
        }
        failoverAttempted = true
        isUsingFallback = true
        resumePosition = currentTime
        let fallbackURL = ContentService.fallbackAudioURL(fileName: fileName)
        startPlayback(url: fallbackURL)
    }

    // MARK: - Controls

    func pause() {
        savePosition()
        pendingPlay = false
        player?.pause()
        isPlaying = false
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
        let upper = duration > 0 ? duration : seconds
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
        UserDefaults.standard.set(rate, forKey: Keys.playbackRate)
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
        currentLessonID = nil
        currentLessonTitle = nil
        currentChapterTitle = nil
        isPlaying = false
        isLoading = false
        currentTime = 0
        duration = 0
        errorMessage = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    @objc private func playerItemFinished(_ notification: Notification) {
        guard !didFireFinished else { return }
        didFireFinished = true
        pendingPlay = false
        isPlaying = false
        if let lessonID = currentLessonID {
            clearSavedPosition(for: lessonID)
            // Narration played to the end: record the real listening
            // time (only a finished listen counts; partial listens
            // are not recorded, so learning hours are never estimated).
            if currentTime > 0 {
                ProgressStore.shared.recordAudioListened(lessonID: lessonID, seconds: Int(currentTime))
            }
        }
        updateNowPlayingInfo()
        DispatchQueue.main.async { [weak self] in
            self?.onFinished?()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
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
