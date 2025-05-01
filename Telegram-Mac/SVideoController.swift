//
//  VideoStreamingTestModalController.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 12/11/2018.
//  Copyright © 2018 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import TelegramCore
import TelegramMediaPlayer
import SwiftSignalKit
import Postbox
import RangeSet
import IOKit.pwr_mgt
import TelegramMedia


private func makePlayer(account: Account, reference: FileMediaReference, fetchAutomatically: Bool = false) -> (UniversalVideoContentView & NSView) {
    let player: (UniversalVideoContentView & NSView)
    if isHLSVideo(file: reference.media) {
        player = HLSVideoJSNativeContentView(accountId: account.id, postbox: account.postbox, userLocation: reference.userLocation, fileReference: reference, streamVideo: true, loopVideo: false, enableSound: true, baseRate: FastSettings.playingVideoRate, fetchAutomatically: false, volume: FastSettings.volumeRate, initialQuality: FastSettings.videoQuality)
    } else {
        player = NativeMediaPlayer(postbox: account.postbox, reference: reference, fetchAutomatically: fetchAutomatically)
    }
    return player
}

enum SVideoStyle {
    case regular
    case pictureInPicture
}



class SVideoController: GenericViewController<SVideoView>, PictureInPictureControl {
    
    
   
    
    
    var style: SVideoStyle = .regular
    private var fullScreenWindow: Window?
    private var fullScreenRestoreState: (rect: NSRect, view: NSView)?
    private(set) var mediaPlayer: (UniversalVideoContentView & NSView)!
    private let reference: FileMediaReference
    private let statusDisposable = MetaDisposable()
    private let bufferingDisposable = MetaDisposable()
    private let hideOnIdleDisposable = MetaDisposable()
    private let hideControlsDisposable = MetaDisposable()
    private let account: Account
    private var pictureInPicture: Bool = false
    private var hideControls: ValuePromise<Bool> = ValuePromise(true, ignoreRepeated: true)
    private var controlsIsHidden: Bool = false
    var togglePictureInPictureImpl:((Bool, PictureInPictureControl)->Void)?
    
    private var isPaused: Bool = true
    private var forceHiddenControls: Bool = false
    private var _videoFramePreview: MediaPlayerFramePreview?
    private var mode: PictureInPictureControlMode = .normal
    
    private var updateControls: SwiftSignalKit.Timer?
    
    private var videoFramePreview: MediaPlayerFramePreview? {
        if let videoFramePreview = _videoFramePreview {
            return videoFramePreview
        } else {
            let qualityState = self.genericView.mediaPlayer.videoQualityState()
            if let qualityState = qualityState, !qualityState.available.isEmpty {
                if let minQuality = HLSVideoContent.minimizedHLSQuality(file: reference)?.file {
                    self._videoFramePreview = MediaPlayerFramePreview(postbox: account.postbox, fileReference: minQuality)
                } else {
                    _videoFramePreview = nil
                }
            } else {
                self._videoFramePreview = MediaPlayerFramePreview(postbox: account.postbox, fileReference: reference)
            }
        }
        return _videoFramePreview
    }
    
    
    func setMode(_ mode: PictureInPictureControlMode, animated: Bool) {
        genericView.setMode(mode, animated: animated)
        self.mode = mode
    }
    
    private var scrubbingFrame = Promise<MediaPlayerFramePreviewResult?>(nil)
    private var scrubbingFrames = false
    private var scrubbingFrameDisposable: Disposable?
    private let isProtected: Bool
    private let isControlsLimited: Bool
    private let message: Message?
    
    private let partDisposable = MetaDisposable()
    
    private let mediaPlaybackStateDisposable = MetaDisposable()
    
    private var endPlaybackId: Int?
    
    init(account: Account, reference: FileMediaReference, message: Message?, fetchAutomatically: Bool = false, isProtected: Bool = false, isControlsLimited: Bool = false) {
        self.reference = reference
        self.account = account
        self.isProtected = isProtected
        self.isControlsLimited = isControlsLimited
        self.message = message
        super.init()
        bar = .init(height: 0)
    }
    
    var status: Signal<MediaPlayerStatus, NoError> {
        return mediaPlayer.status
    }
    
    func play(_ startTime: TimeInterval? = nil) {
        mediaPlayer.play()
        self.isPaused = false
        if let startTime = startTime, startTime > 0 {
            mediaPlayer.seek(startTime)
        }
    }
    
    func setBaseRate(_ baseRate: Double) {        
        mediaPlayer.setBaseRate(baseRate)
        FastSettings.setPlayingVideoRate(baseRate)
    }
    
    func playOrPause() {
        self.isPaused = !self.isPaused
        mediaPlayer.togglePlayPause()
    }
    
    func pause() {
        self.isPaused = true
        mediaPlayer.pause()
    }
    
    func play() {
        self.isPaused = false
        self.play(nil)
    }
    
    
    func didEnter() {
        
    }
    
    func didExit() {
        
    }
    
    func isPlaying() -> Bool {
        return !self.isPaused
    }
    
    private func updateIdleTimer() {
        NSCursor.unhide()
        hideOnIdleDisposable.set((Signal<NoValue, NoError>.complete() |> delay(1.0, queue: Queue.mainQueue())).start(completed: { [weak self] in
            guard let `self` = self else {return}
            let hide = !self.genericView.isInMenu && !self.genericView.insideControls
            self.hideControls.set(hide)
            if !self.pictureInPicture, !self.isPaused, hide {
                if !contextMenuOnScreen() {
                    NSCursor.hide()
                }
            }
        }))
    }
    
    private func updateControlVisibility(_ isMouseUpOrDown: Bool = false) {
        updateIdleTimer()
        
        
        if let rootView = genericView.superview?.superview {
            var hide = !genericView._mouseInside() && !rootView.isHidden && (NSEvent.pressedMouseButtons & (1 << 0)) == 0
            
           
            if !hide, (NSEvent.pressedMouseButtons & (1 << 0)) != 0 {
                hide = genericView.controlsStyle.isPip
            }

            
            if self.fullScreenWindow != nil && isMouseUpOrDown, !genericView.insideControls {
                hide = true
                if !self.isPaused {
                    if !contextMenuOnScreen() {
                        NSCursor.hide()
                    }
                }
            }
            if contextMenuOnScreen() {
                hide = false
            }
            hideControls.set(hide || forceHiddenControls)
        } else {
            hideControls.set(forceHiddenControls)
        }
    }
    
    
    
    private func setHandlersOn(window: Window) {
        
        updateIdleTimer()
        
        let mouseInsidePlayer = genericView.mediaPlayer._mouseInside()
        
        hideControls.set(!mouseInsidePlayer || forceHiddenControls)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            if let window = self?.genericView.window, let contentView = window.contentView {
                let point = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if contentView.hitTest(point) != nil {
                    self?.updateControlVisibility()
                }
            }
            return .rejected
        }, with: self, for: .mouseMoved, priority: .modal)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            if let window = self?.genericView.window, let contentView = window.contentView {
                let point = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if contentView.hitTest(point) != nil {
                    self?.updateControlVisibility()
                }
            }
            return .rejected
        }, with: self, for: .mouseExited, priority: .modal)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            self?.updateIdleTimer()
            
            return .rejected
        }, with: self, for: .leftMouseDragged, priority: .modal)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            if let window = self?.genericView.window, let contentView = window.contentView {
                let point = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if contentView.hitTest(point) != nil {
                    self?.updateControlVisibility()
                }
            }
            return .rejected
        }, with: self, for: .mouseEntered, priority: .modal)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            if self?.genericView.mediaPlayer._mouseInside() == true {
                self?.updateControlVisibility(true)
            }
            return .rejected
        }, with: self, for: .leftMouseDown, priority: .modal)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            guard let `self` = self else {return .rejected}
            if let window = self.genericView.window, let contentView = window.contentView {
                let point = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if contentView.hitTest(point) != nil {
                    self.updateControlVisibility(true)
                }
            }
            self.genericView.subviews.last?.mouseUp(with: event)
            return .rejected
        }, with: self, for: .leftMouseUp, priority: .modal)
        
//        self.updateControls = SwiftSignalKit.Timer(timeout: 2.0, repeat: true, completion: { [weak self] in
//            self?.updateControlVisibility()
//        }, queue: .mainQueue())
//
//        self.updateControls?.start()
        
    }
    
    private var assertionID: IOPMAssertionID = 0
    private var success: IOReturn?
    
    private func disableScreenSleep() -> Bool? {
        guard success == nil else { return nil }
        success = IOPMAssertionCreateWithName( kIOPMAssertionTypeNoDisplaySleep as CFString,
                                               IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "Video Playing" as CFString,
                                               &assertionID )
        return success == kIOReturnSuccess
    }
    
    private func  enableScreenSleep() -> Bool {
        if success != nil {
            success = IOPMAssertionRelease(assertionID)
            success = nil
            return true
        }
        return false
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
      
        if let window = window {
            setHandlersOn(window: window)
        }
        
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        hideOnIdleDisposable.set(nil)
        _ = enableScreenSleep()
        NSCursor.unhide()
        window?.removeAllHandlers(for: self)
        
    }
    
    var isPictureInPicture: Bool {
        return self.pictureInPicture
    }
    
    
    func hideControlsIfNeeded(_ forceHideControls: Bool = false) -> Bool {
        self.forceHiddenControls = forceHideControls
        if !controlsIsHidden {
            hideControls.set(true)
            return true
        }
        
        return false
    }
    
    func unhideControlsIfNeeded(_ forceUnhideControls: Bool = true) -> Bool {
        forceHiddenControls = !forceUnhideControls
        if controlsIsHidden {
            hideControls.set(forceUnhideControls)
            return true
        }
        return false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let account = self.account
        
        if isHLSVideo(file: reference.media) {
            let fetchSignal = HLSVideoContent.minimizedHLSQualityPreloadData(postbox: account.postbox, file: reference, userLocation: .other, prefixSeconds: 10, autofetchPlaylist: true, initialQuality: FastSettings.videoQuality)
            |> mapToSignal { fileAndRange -> Signal<Never, NoError> in
                guard let fileAndRange else {
                    return .complete()
                }
                return freeMediaFileResourceInteractiveFetched(postbox: account.postbox, userLocation: .other, fileReference: fileAndRange.0, resource: fileAndRange.0.media.resource, range: (fileAndRange.1, .default))
                |> ignoreValues
                |> `catch` { _ -> Signal<Never, NoError> in
                    return .complete()
                }
            }
            partDisposable.set(fetchSignal.start())
        } else {
            let preload = preloadVideoResource(postbox: account.postbox, userLocation: .other, userContentType: .init(file: reference.media), resourceReference: reference.resourceReference(reference.media.resource), duration: 3.0)
            partDisposable.set(preload.start())
        }

        
        genericView.layerContentsRedrawPolicy = .duringViewResize

        
        genericView.isControlsLimited = isControlsLimited
        
        
        genericView.isStreamable = reference.media.isStreamable
        hideControlsDisposable.set(hideControls.get().start(next: { [weak self] hide in
            self?.genericView.hideControls(hide, animated: true)
            self?.controlsIsHidden = hide
        }))
        
        
        let statusValue:Atomic<MediaPlayerStatus?> = Atomic(value: nil)
        let updateTemporaryStatus:(_ f: (MediaPlayerStatus?)->MediaPlayerStatus?) -> Void = { [weak self] f in
            self?.genericView.status = statusValue.modify(f)
        }
        
        let duration = Double(reference.media.duration ?? 0)
        
        statusDisposable.set((mediaPlayer.status |> deliverOnMainQueue).start(next: { [weak self] status in
            let status = status.withUpdatedDuration(status.duration != 0 ? status.duration : duration)
            switch status.status {
            case .playing:
                _ = self?.disableScreenSleep()
            case let .buffering(_, whilePlaying):
                if whilePlaying {
                    _ = self?.disableScreenSleep()
                } else {
                    _ = self?.enableScreenSleep()
                }
            case .paused:
                _ = self?.enableScreenSleep()
            }
            _ = statusValue.swap(status)
           
            self?.genericView.status = status
        }))
        let size = reference.media.resource.size ?? 0
        
        let bufferingStatus = mediaPlayer.bufferingStatus |> deliverOnMainQueue
        
        bufferingDisposable.set(bufferingStatus.start(next: { [weak self] bufferingStatus in
            self?.genericView.bufferingStatus = bufferingStatus
        }))
        
        self.scrubbingFrameDisposable = (self.scrubbingFrame.get()
            |> deliverOnMainQueue).start(next: { [weak self] result in
                guard let `self` = self else {
                    return
                }
            let live = (NSEvent.pressedMouseButtons & (1 << 0)) != 0 && self.genericView.mouseDownIncontrols
                if let result = result {
                    self.genericView.showScrubblerPreviewIfNeeded(live: live)
                    self.genericView.setCurrentScrubblingState(result, live: live)
                } else {
                    self.genericView.hideScrubblerPreviewIfNeeded(live: live)
                    // empty image
                }
            })

        var paused: Bool? = nil
        
        genericView.interactions = SVideoInteractions(playOrPause: { [weak self] in
            self?.playOrPause()
        }, rewind: { [weak self] timestamp in
            self?.mediaPlayer.seek(timestamp)
        }, scrobbling: { [weak self] timecode in
            guard let `self` = self else { return }

            if let timecode = timecode, let videoFramePreview = self.videoFramePreview {
                if !self.scrubbingFrames {
                    self.scrubbingFrames = true
                    self.scrubbingFrame.set(videoFramePreview.generatedFrames
                        |> map(Optional.init))
                }
                videoFramePreview.generateFrame(at: timecode)
            } else {
                self.scrubbingFrame.set(.single(nil))
                self.videoFramePreview?.cancelPendingFrames()
                self.scrubbingFrames = false
            }
        }, volume: { [weak self] value in
            self?.mediaPlayer.setVolume(value)
            FastSettings.setVolumeRate(value)
            updateTemporaryStatus { status in
                return status?.withUpdatedVolume(value)
            }
        }, toggleFullScreen: { [weak self] in
            self?.toggleFullScreen()
        }, togglePictureInPicture: { [weak self] in
            self?.togglePictureInPicture()
        }, closePictureInPicture: {
            closePipVideo()
        }, setBaseRate: { [weak self] rate in
            self?.setBaseRate(rate)
        }, pause: { [weak self] in
            if self?.isPaused == false {
                self?.pause()
                paused = true
            }
        }, play: { [weak self] in
            if paused == true {
                self?.play()
                paused = nil
            }
        })
        
        if let duration = reference.media.duration, duration < 30 {
            endPlaybackId = mediaPlayer.addPlaybackCompleted { [weak self] in
                Queue.mainQueue().async {
                    self?.mediaPlayer.seek(0)
                    self?.mediaPlayer.play()
                    self?.updateIdleTimer()
                }
            }
        } else {
            endPlaybackId = mediaPlayer.addPlaybackCompleted { [weak self] in
                DispatchQueue.main.async {
                    if let duration = self?.mediaPlayer.duration, duration < 30 {
                        self?.mediaPlayer.seek(0)
                        self?.mediaPlayer.play()
                    }
                    self?.hideControls.set(false)
                    self?.updateIdleTimer()
                }
            }
        }
        
        
        if let message {
            let throttledSignal = self.mediaPlayer.status
            |> mapToThrottled { next -> Signal<MediaPlayerStatus, NoError> in
                return .single(next) |> then(.complete() |> delay(2.0, queue: Queue.concurrentDefaultQueue()))
            }
            
            self.mediaPlaybackStateDisposable.set(throttledSignal.startStrict(next: { status in
                if status.duration >= 10, case .playing = status.status {
                    let storedState = MediaPlaybackStoredState(timestamp: status.timestamp)
                    let _ = updateMediaPlaybackStoredStateInteractively(engine: TelegramEngine(account: account), messageId: message.id, state: storedState).startStandalone()
                }
            }))
        }
        


        
        
        readyOnce()
    }
    
    func togglePictureInPicture() {
        if let function = togglePictureInPictureImpl {
            if fullScreenRestoreState != nil {
                toggleFullScreen()
            }
            self.pictureInPicture = !pictureInPicture
            window?.removeAllHandlers(for: self)
            function(pictureInPicture, self)
            if let window = view.window?.contentView?.window as? Window {
                setHandlersOn(window: window)
            }
            
            genericView.set(isInPictureInPicture: pictureInPicture)
        }
    }
    
    func togglePlayerOrPause() {
        playOrPause()
    }
    
    
    func rewindBackward() {
        genericView.rewindBackward()
    }
    func rewindForward() {
        genericView.rewindForward()
    }
    
    var isFullscreen: Bool {
        return self.fullScreenRestoreState != nil
    }
    
    func toggleFullScreen() {
        if let screen = NSScreen.main {
            if let window = fullScreenWindow, let state = fullScreenRestoreState {
                
                var topInset: CGFloat = 0
                
                if #available(macOS 12.0, *) {
                    topInset = screen.safeAreaInsets.top
                }
                
                
                window.setFrame(NSMakeRect(screen.frame.minX + state.rect.minX, screen.frame.minY + screen.frame.height - state.rect.maxY - topInset, state.rect.width, state.rect.height), display: true, animate: true)
                window.orderOut(nil)
                view.frame = state.rect
                state.view.addSubview(view)
                
                genericView.set(isInFullScreen: false)
                mediaPlayer.setVideoLayerGravity(.resizeAspectFill)

                
                window.removeAllHandlers(for: self)
                if let window = self.window {
                    setHandlersOn(window: window)
                }
                
                self.fullScreenWindow = nil
                self.fullScreenRestoreState = nil
            } else {
                
                mediaPlayer.setVideoLayerGravity(.resizeAspect)

                
                fullScreenRestoreState = (rect: view.frame, view: view.superview!)
                fullScreenWindow = Window(contentRect: NSMakeRect(view.frame.minX, screen.frame.height - view.frame.maxY, view.frame.width, view.frame.height), styleMask: [.fullSizeContentView, .borderless], backing: .buffered, defer: true, screen: screen)
                
                setHandlersOn(window: fullScreenWindow!)
                window?.removeAllHandlers(for: self)
                
                
                fullScreenWindow?.isOpaque = true
                fullScreenWindow?.hasShadow = false
                fullScreenWindow?.level = .screenSaver
                self.view.frame = self.view.bounds
                fullScreenWindow?.contentView?.addSubview(self.view)
                fullScreenWindow?.orderFront(nil)
                genericView.set(isInFullScreen: true)
                fullScreenWindow?.becomeKey()
                fullScreenWindow?.setFrame(screen.frame, display: true, animate: true)
            }
        }
    }
    
    override func initializer() -> SVideoView {
        mediaPlayer = makePlayer(account: account, reference: reference)
        return SVideoView(frame: _frameRect, mediaPlayer: self.mediaPlayer)
    }
    
    deinit {
        statusDisposable.dispose()
        bufferingDisposable.dispose()
        hideOnIdleDisposable.dispose()
        hideControlsDisposable.dispose()
        mediaPlaybackStateDisposable.dispose()
        partDisposable.dispose()
        if let endPlaybackId {
            mediaPlayer.removePlaybackCompleted(endPlaybackId)
        }
        updateControls?.invalidate()
        _ = IOPMAssertionRelease(assertionID)
        NSCursor.unhide()
    }
    
}
