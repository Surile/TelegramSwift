//
//  GroupCallController.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 22/11/2020.
//  Copyright © 2020 Telegram. All rights reserved.
//

import Foundation
import TGUIKit
import SwiftSignalKit
import Postbox
import SyncCore
import TelegramCore
import HotKey

private final class GroupCallUIArguments {
    let leave:()->Void
    let settings:()->Void
    let invite:(PeerId)->Void
    let mute:(PeerId, Bool, Int32?)->Void
    let toggleSpeaker:()->Void
    let remove:(Peer)->Void
    let openInfo: (PeerId)->Void
    let inviteMembers:()->Void
    let shareSource:()->Void
    let takeVideo:(PeerId)->NSView?
    let setVolume: (PeerId, Double, Bool) -> Void
    let pinVideo:(PeerId, UInt32)->Void
    let unpinVideo:()->Void
    let isPinnedVideo:(PeerId)->Bool
    let getAccountPeerId: ()->PeerId?
    let cancelSharing: ()->Void
    init(leave:@escaping()->Void,
    settings:@escaping()->Void,
    invite:@escaping(PeerId)->Void,
    mute:@escaping(PeerId, Bool, Int32?)->Void,
    toggleSpeaker:@escaping()->Void,
    remove:@escaping(Peer)->Void,
    openInfo: @escaping(PeerId)->Void,
    inviteMembers:@escaping()->Void,
    shareSource: @escaping()->Void,
    takeVideo:@escaping(PeerId)->NSView?,
    pinVideo:@escaping(PeerId, UInt32)->Void,
    unpinVideo:@escaping()->Void,
    isPinnedVideo:@escaping(PeerId)->Bool,
    setVolume: @escaping(PeerId, Double, Bool)->Void,
    getAccountPeerId: @escaping()->PeerId?,
    cancelSharing: @escaping()->Void) {
        self.leave = leave
        self.invite = invite
        self.mute = mute
        self.settings = settings
        self.toggleSpeaker = toggleSpeaker
        self.remove = remove
        self.openInfo = openInfo
        self.inviteMembers = inviteMembers
        self.shareSource = shareSource
        self.takeVideo = takeVideo
        self.pinVideo = pinVideo
        self.unpinVideo = unpinVideo
        self.isPinnedVideo = isPinnedVideo
        self.setVolume = setVolume
        self.getAccountPeerId = getAccountPeerId
        self.cancelSharing = cancelSharing
    }
}

private final class GroupCallControlsView : View {
    private let speak: GroupCallSpeakButton = GroupCallSpeakButton(frame: NSMakeRect(0, 0, 144, 144))
    private let videoStream: CallControl = CallControl(frame: .zero)
    private let end: CallControl = CallControl(frame: .zero)
    private var speakText: TextView?
    fileprivate var arguments: GroupCallUIArguments?

    private let backgroundView = VoiceChatActionButtonBackgroundView()

    required init(frame frameRect: NSRect) {


        super.init(frame: frameRect)

        addSubview(backgroundView)

        addSubview(videoStream)
        addSubview(end)

        addSubview(speak)
        
        self.isEventLess = true


        end.set(handler: { [weak self] _ in
            self?.arguments?.leave()
        }, for: .Click)
        

        
        speak.set(handler: { [weak self] _ in
            if let muteState = self?.preiousState?.muteState, !muteState.canUnmute {
                self?.speakText?.shake()
                NSSound.beep()
            } else {
                self?.arguments?.toggleSpeaker()
            }
        }, for: .Click)

    }
    
    private var preiousState: PresentationGroupCallState?
    
    private var clickToken:UInt32?
    func update(_ callState: GroupCallUIState, voiceSettings: VoiceCallSettings, audioLevel: Float?, animated: Bool) {



        let state = callState.state
        speak.update(with: state, isMuted: callState.isMuted, audioLevel: audioLevel, animated: animated)

        let isStreaming: Bool
        if let arguments = arguments, let peerId = arguments.getAccountPeerId() {
            isStreaming = callState.activeVideoSources[peerId] != nil
        } else {
            isStreaming = false
        }

        if let clickToken = clickToken {
            videoStream.removeHandler(clickToken)
        }
        clickToken = videoStream.set(handler: { [weak self] _ in
            if !isStreaming {
                self?.arguments?.shareSource()
            } else {
                self?.arguments?.cancelSharing()
            }
        }, for: .Click)

        var backgroundState: VoiceChatActionButtonBackgroundView.State
        
        switch state.networkState {
            case .connected:
                if callState.isMuted {
                    if let muteState = callState.state.muteState {
                        if muteState.canUnmute {
                            backgroundState = .blob(false)
                        } else {
                            backgroundState = .disabled
                        }
                    } else {
                        backgroundState = .blob(true)
                    }
                } else {
                    backgroundState = .blob(true)
                }
            case .connecting:
                backgroundState = .connecting
        }
        self.backgroundView.isDark = false
        self.backgroundView.update(state: backgroundState, animated: animated)

        self.backgroundView.audioLevel = CGFloat(audioLevel ?? 0)

      //  if state != preiousState {
            end.updateWithData(CallControlData(text: L10n.voiceChatLeave, isVisualEffect: false, icon: GroupCallTheme.declineIcon, iconSize: NSMakeSize(48, 48), backgroundColor: GroupCallTheme.declineColor), animated: animated)

            videoStream.updateWithData(CallControlData(text: L10n.voiceChatVideoStream, isVisualEffect: false, icon: isStreaming ? GroupCallTheme.video_off : GroupCallTheme.video_on, iconSize: NSMakeSize(48, 48), backgroundColor: GroupCallTheme.settingsColor), animated: animated)
      //  }
        let statusText: String
        var secondary: String? = nil
        switch state.networkState {
        case .connected:
            if callState.isMuted {
                if let muteState = state.muteState {
                    if muteState.canUnmute {
                        statusText = L10n.voiceChatClickToUnmute
                        switch voiceSettings.mode {
                        case .always:
                            if let pushToTalk = voiceSettings.pushToTalk, !pushToTalk.isSpace {
                                secondary = L10n.voiceChatClickToUnmuteSecondaryPress(pushToTalk.string)
                            } else {
                                secondary = L10n.voiceChatClickToUnmuteSecondaryPressDefault
                            }
                        case .pushToTalk:
                            if let pushToTalk = voiceSettings.pushToTalk, !pushToTalk.isSpace {
                                secondary = L10n.voiceChatClickToUnmuteSecondaryHold(pushToTalk.string)
                            } else {
                                secondary = L10n.voiceChatClickToUnmuteSecondaryHoldDefault
                            }
                        case .none:
                            secondary = nil
                        }
                    } else {
                        statusText = L10n.voiceChatMutedByAdmin
                        secondary = L10n.voiceChatListenMode
                    }
                } else {
                    statusText = L10n.voiceChatYouLive
                }
            } else {
                statusText = L10n.voiceChatYouLive
            }
        case .connecting:
            statusText = L10n.voiceChatConnecting
        }

        let string = NSMutableAttributedString()
        string.append(.initialize(string: statusText, color: .white, font: .medium(.title)))
        if let secondary = secondary {
            string.append(.initialize(string: "\n", color: .white, font: .medium(.text)))
            string.append(.initialize(string: secondary, color: .white, font: .normal(.short)))
        }

        if string.string != self.speakText?.layout?.attributedString.string {
            let speakText = TextView()
            speakText.userInteractionEnabled = false
            speakText.isSelectable = false
            let layout = TextViewLayout(string, alignment: .center)
            layout.measure(width: frame.width - 60)
            speakText.update(layout)

            if let speakText = self.speakText {
                self.speakText = nil
                if animated {
                    speakText.layer?.animateAlpha(from: 1, to: 0, duration: 0.3, removeOnCompletion: false, completion: { [weak speakText] _ in
                        speakText?.removeFromSuperview()
                    })
                    speakText.layer?.animateScaleSpring(from: 1, to: 0.2, duration: 0.5)
                } else {
                    speakText.removeFromSuperview()
                }
            }


            self.speakText = speakText
            addSubview(speakText)
            speakText.centerX(y: speak.frame.maxY + floorToScreenPixels(backingScaleFactor, ((frame.height - speak.frame.maxY) - speakText.frame.height) / 2) - 33)
            if animated {
                speakText.layer?.animateAlpha(from: 0, to: 1, duration: 0.3)
                speakText.layer?.animateScaleSpring(from: 0.2, to: 1, duration: 0.5)
            }
        }

        self.preiousState = state
        needsLayout = true
    }
    
    override var mouseDownCanMoveWindow: Bool {
        return true
    }


    private var blue:NSColor {
        return GroupCallTheme.speakInactiveColor
    }

    private var lightBlue: NSColor {
        return NSColor(rgb: 0x59c7f8)
    }

    private var green: NSColor {
        return GroupCallTheme.speakActiveColor
    }

    
    override func layout() {
        super.layout()
        speak.center()

        videoStream.centerY(x: 30)
        end.centerY(x: frame.width - end.frame.width - 30)
        if let speakText = speakText {
            speakText.centerX(y: speak.frame.maxY + floorToScreenPixels(backingScaleFactor, ((frame.height - speak.frame.maxY) - speakText.frame.height) / 2 - 33))
        }

        self.backgroundView.frame = focus(.init(width: 360, height: 360))

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class GroupCallTitleView : View {
    fileprivate let titleView: TextView = TextView()
    fileprivate let statusView: DynamicCounterTextView = DynamicCounterTextView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(titleView)
        addSubview(statusView)
        titleView.isSelectable = false
        titleView.userInteractionEnabled = false
        statusView.userInteractionEnabled = false
    }
    
    override var backgroundColor: NSColor {
        didSet {
            titleView.backgroundColor = backgroundColor
            statusView.backgroundColor = backgroundColor
        }
    }
    
    override var mouseDownCanMoveWindow: Bool {
        return true
    }
    
    override func layout() {
        super.layout()
        titleView.centerX(y: frame.midY - titleView.frame.height)
        statusView.centerX(y: frame.midY)
    }
    
    
    func update(_ peer: Peer, _ state: GroupCallUIState, animated: Bool) {
        let layout = TextViewLayout(.initialize(string: peer.displayTitle, color: GroupCallTheme.titleColor, font: .medium(.title)), maximumNumberOfLines: 1)
        layout.measure(width: frame.width - 180)
        titleView.update(layout)


        let status: String
        let count: Int
        if let summaryState = state.summaryState {
            status = L10n.voiceChatStatusMembersCountable(summaryState.participantCount)
            count = summaryState.participantCount
        } else {
            status = L10n.voiceChatStatusLoading
            count = 0
        }

        let dynamicResult = DynamicCounterTextView.make(for: status, count: "\(count)", font: .normal(.text), textColor: GroupCallTheme.grayStatusColor, width: frame.width - 140)

        self.statusView.update(dynamicResult.values, animated: animated)

        self.statusView.change(size: dynamicResult.size, animated: animated)
        self.statusView.change(pos: NSMakePoint(floorToScreenPixels(backingScaleFactor, (frame.width - dynamicResult.size.width) / 2), frame.midY), animated: animated)

        needsLayout = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}



private final class MainVideoContainerView: View {
    private let call: PresentationGroupCall
    
    private var currentVideoView: GroupVideoView?
    private var currentPeer: (PeerId, UInt32)?
    
    private var validLayout: CGSize?
    
    init(call: PresentationGroupCall) {
        self.call = call
        
        super.init()
        
        self.backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    func updatePeer(peer: (peerId: PeerId, source: UInt32)?) {
        if self.currentPeer?.0 == peer?.0 && self.currentPeer?.1 == peer?.1 {
            return
        }
        self.currentPeer = peer
        if let (peerId, source) = peer {
            self.call.makeVideoView(source: source, completion: { [weak self] videoView in
                Queue.mainQueue().async {
                    guard let strongSelf = self, let videoView = videoView else {
                        return
                    }
                    let videoViewValue = GroupVideoView(videoView: videoView)
                    if let currentVideoView = strongSelf.currentVideoView {
                        currentVideoView.removeFromSuperview()
                        strongSelf.currentVideoView = nil
                    }
                    strongSelf.currentVideoView = videoViewValue
                    strongSelf.addSubview(videoViewValue)
                    if let size = strongSelf.validLayout {
                        strongSelf.update(size: size, transition: .immediate)
                    }
                }
            })
        } else {
            if let currentVideoView = self.currentVideoView {
                currentVideoView.removeFromSuperview()
                self.currentVideoView = nil
            }
        }
    }
    
    func update(size: CGSize, transition: ContainedViewLayoutTransition) {
        self.validLayout = size
        
        if let currentVideoView = self.currentVideoView {
            currentVideoView.frame = CGRect(origin: CGPoint(), size: size)
           // transition.updateFrame(node: currentVideoView, frame: CGRect(origin: CGPoint(), size: size))
            currentVideoView.updateLayout(size: size, transition: .immediate)
        }
    }
    
    override func layout() {
        super.layout()
        update(size: frame.size, transition: .immediate)
    }
}


private final class GroupCallView : View {
    let peersTable: TableView = TableView(frame: NSMakeRect(0, 0, 340, 329))
    let titleView: GroupCallTitleView = GroupCallTitleView(frame: NSMakeRect(0, 0, 380, 54))
    private let peersTableContainer: View = View(frame: NSMakeRect(0, 0, 340, 329))
    private let controlsContainer = GroupCallControlsView(frame: .init(x: 0, y: 0, width: 360, height: 320))
    
    private var mainVideoView: MainVideoContainerView? = nil
    
    fileprivate var arguments: GroupCallUIArguments? {
        didSet {
            controlsContainer.arguments = arguments
        }
    }
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(titleView)
        addSubview(peersTableContainer)
        addSubview(peersTable)
        addSubview(controlsContainer)
        peersTableContainer.layer?.cornerRadius = 10
        peersTable.layer?.cornerRadius = 10
        updateLocalizationAndTheme(theme: theme)

        peersTable._mouseDownCanMoveWindow = true
        
        peersTable.getBackgroundColor = {
            .clear
        }
        peersTable.addScroll(listener: TableScrollListener(dispatchWhenVisibleRangeUpdated: false, { [weak self] pos in
            guard let `self` = self else {
                return
            }
            self.peersTableContainer.frame = self.substrateRect()
        }))
    }
    
    private func substrateRect() -> NSRect {
        var h = self.peersTable.listHeight
        if peersTable.documentOffset.y < 0 {
            h -= peersTable.documentOffset.y
        }
        h = min(h, self.peersTable.frame.height)
        return .init(origin:  tableRect.origin, size: NSMakeSize(self.peersTable.frame.width, h))

    }
    
    override var mouseDownCanMoveWindow: Bool {
        return true
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        peersTableContainer.backgroundColor = GroupCallTheme.membersColor
        backgroundColor = GroupCallTheme.windowBackground
        titleView.backgroundColor = GroupCallTheme.windowBackground
    }
    
    override func layout() {
        super.layout()
        peersTable.frame = tableRect
        peersTableContainer.frame = substrateRect()
        controlsContainer.centerX(y: frame.height - controlsContainer.frame.height + 50)
    }
    
    
    private var tableRect: NSRect {
        var size = peersTable.frame.size
        if mainVideoView != nil {
            size = NSMakeSize(340, 41 + 48 * 2)
        } else {
            size = NSMakeSize(340, 329)
        }
        var rect = focus(size)
        rect.origin.y = 53
        
        if mainVideoView != nil {
            rect.origin.y = mainVideoRect.maxY + 10
        }
        return rect
    }
    
    private var mainVideoRect: NSRect {
        var rect = focus(.init(width: peersTable.frame.width, height: 180))
        rect.origin.y = 53
        return rect
    }
    
    func applyUpdates(_ state: GroupCallUIState, _ transition: TableUpdateTransition, _ call: PresentationGroupCall, animated: Bool) {
        peersTable.merge(with: transition)
        titleView.update(state.peer, state, animated: animated)
        controlsContainer.update(state, voiceSettings: state.voiceSettings, audioLevel: state.myAudioLevel, animated: animated)
        
        peersTableContainer.change(size: substrateRect().size, animated: animated)
        
        if let currentDominantSpeakerWithVideo = state.currentDominantSpeakerWithVideo {
            let mainVideo: MainVideoContainerView
            var isPresented: Bool = false
            if let video = self.mainVideoView {
                mainVideo = video
            } else {
                mainVideo = MainVideoContainerView(call: call)
                mainVideo.frame = mainVideoRect
                mainVideo.layer?.cornerRadius = 10
                self.mainVideoView = mainVideo
                addSubview(mainVideo)
                isPresented = true
            }
            mainVideo.updatePeer(peer: currentDominantSpeakerWithVideo)
            
            if isPresented && animated {
                mainVideo.layer?.animateAlpha(from: 0, to: 1, duration: 0.3)
                mainVideo.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.4, bounce: false)
            }
        } else {
            if let mainVideo = self.mainVideoView {
                self.mainVideoView = nil
                if animated {
                    mainVideo.layer?.animateAlpha(from: 1, to: 0, duration: 0.3, removeOnCompletion: false, completion: { [weak mainVideo] _ in
                        mainVideo?.removeFromSuperview()
                    })
                    mainVideo.layer?.animateScaleSpring(from: 1, to: 0.01, duration: 0.1, removeOnCompletion: false, bounce: false)
                } else {
                    mainVideo.removeFromSuperview()
                }
            }
        }
        peersTable.change(pos: tableRect.origin, animated: animated)
        peersTable.change(size: tableRect.size, animated: animated)
        
        peersTableContainer.change(pos: substrateRect().origin, animated: animated)
        peersTableContainer.change(size: substrateRect().size, animated: animated)

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


struct PeerGroupCallData : Equatable, Comparable {
    struct AudioLevel {
        let timestamp: Int32
        let value: Float
    }

    let peer: Peer
    let presence: TelegramUserPresence?
    let state: GroupCallParticipantsContext.Participant?
    let isSpeaking: Bool
    let audioLevel: Float?
    let isInvited: Bool
    let isKeyWindow: Bool
    let unsyncVolume: Int32?
    let isRecentActive: Bool
    let activeIndex: Int?
    let isPinned: Bool
    private var weight: Int {
        var weight: Int = 0
        
        if let _ = state {
            if isSpeaking {
                weight += (1 << 30)
            } else {
                if isRecentActive {
                    weight += (1 << 29)
                } else {
                    weight += (1 << 28)
                }
            }
        }
        if isPinned {
            weight += (1 << 31)
        }
        return weight
    }
    
    static func ==(lhs: PeerGroupCallData, rhs: PeerGroupCallData) -> Bool {
        if !lhs.peer.isEqual(rhs.peer) {
            return false
        }
        if let lhsPresence = lhs.presence, let rhsPresence = rhs.presence {
            if !lhsPresence.isEqual(to: rhsPresence) {
                return false
            }
        } else if (lhs.presence != nil) != (rhs.presence != nil) {
            return false
        }
        if lhs.state != rhs.state {
            return false
        }
        if lhs.audioLevel != rhs.audioLevel {
            return false
        }
        if lhs.isSpeaking != rhs.isSpeaking {
            return false
        }
        if lhs.isInvited != rhs.isInvited {
            return false
        }
        if lhs.isKeyWindow != rhs.isKeyWindow {
            return false
        }
        if lhs.weight != rhs.weight {
            return false
        }
        if lhs.isPinned != rhs.isPinned {
            return false
        }
        if lhs.unsyncVolume != rhs.unsyncVolume {
            return false
        }
        if lhs.isRecentActive != rhs.isRecentActive {
            return false
        }
        if lhs.activeIndex != rhs.activeIndex {
            return false
        }
        return true
    }
    
    static func <(lhs: PeerGroupCallData, rhs: PeerGroupCallData) -> Bool {
        if let lhsIndex = lhs.activeIndex, let rhsIndex = rhs.activeIndex {
            return lhsIndex < rhsIndex
        }
        return lhs.weight < rhs.weight
    }
}


private final class GroupCallUIState : Equatable {

    struct RecentActive : Equatable {
        let peerId: PeerId
        let timestamp: TimeInterval
    }

    let memberDatas:[PeerGroupCallData]
    let isMuted: Bool
    let state: PresentationGroupCallState
    let summaryState: PresentationGroupCallSummaryState?
    let peer: Peer
    let cachedData: CachedChannelData?
    let myAudioLevel: Float
    let voiceSettings: VoiceCallSettings
    let isKeyWindow: Bool
    let currentDominantSpeakerWithVideo: (PeerId, UInt32)?
    let lastActivity: [RecentActive]
    let activeIndexes: [PeerId : Int]
    let activeVideoSources: [PeerId: UInt32]
    init(memberDatas: [PeerGroupCallData], state: PresentationGroupCallState, isMuted: Bool, summaryState: PresentationGroupCallSummaryState?, myAudioLevel: Float, peer: Peer, cachedData: CachedChannelData?, voiceSettings: VoiceCallSettings, isKeyWindow: Bool, lastActivity: [RecentActive], activeIndexes: [PeerId : Int], currentDominantSpeakerWithVideo: (PeerId, UInt32)?, activeVideoSources: [PeerId: UInt32]) {
        self.summaryState = summaryState
        self.memberDatas = memberDatas
        self.peer = peer
        self.isMuted = isMuted
        self.cachedData = cachedData
        self.state = state
        self.myAudioLevel = myAudioLevel
        self.voiceSettings = voiceSettings
        self.isKeyWindow = isKeyWindow
        self.currentDominantSpeakerWithVideo = currentDominantSpeakerWithVideo
        self.lastActivity = lastActivity
        self.activeIndexes = activeIndexes
        self.activeVideoSources = activeVideoSources
    }
    
    static func == (lhs: GroupCallUIState, rhs: GroupCallUIState) -> Bool {
        if lhs.memberDatas != rhs.memberDatas {
            return false
        }
        if lhs.state != rhs.state {
            return false
        }
        if lhs.myAudioLevel != rhs.myAudioLevel {
            return false
        }
        if lhs.summaryState != rhs.summaryState {
            return false
        }
        if !lhs.peer.isEqual(rhs.peer) {
            return false
        }
        if lhs.voiceSettings != rhs.voiceSettings {
            return false
        }
        if let lhsCachedData = lhs.cachedData, let rhsCachedData = rhs.cachedData {
            if !lhsCachedData.isEqual(to: rhsCachedData) {
                return false
            }
        } else if (lhs.cachedData != nil) != (rhs.cachedData != nil) {
            return false
        }
        if lhs.isKeyWindow != rhs.isKeyWindow {
            return false
        }
        if lhs.currentDominantSpeakerWithVideo?.0 != rhs.currentDominantSpeakerWithVideo?.0 || lhs.currentDominantSpeakerWithVideo?.1 != rhs.currentDominantSpeakerWithVideo?.1 {
            return false
        }
        if lhs.lastActivity != rhs.lastActivity {
            return false
        }
        if lhs.activeIndexes != rhs.activeIndexes {
            return false
        }
        if lhs.activeVideoSources != rhs.activeVideoSources {
            return false
        }
        return true
    }
}

private func makeState(previousActive: [GroupCallUIState.RecentActive], previousActiveIndexes: [PeerId : Int], peerView: PeerView, state: PresentationGroupCallState, isMuted: Bool, invitedPeers: [Peer], peerStates: PresentationGroupCallMembers?, audioLevels: [PeerId : PeerGroupCallData.AudioLevel], summaryState: PresentationGroupCallSummaryState?, voiceSettings: VoiceCallSettings, isKeyWindow: Bool, accountPeer: Peer, unsyncVolumes: [PeerId: Int32], currentDominantSpeakerWithVideo: (PeerId, UInt32)?, activeVideoSources: [PeerId: UInt32]) -> GroupCallUIState {
    
    var memberDatas: [PeerGroupCallData] = []
    
    let accountPeerId = accountPeer.id
    
    var activeParticipants: [GroupCallParticipantsContext.Participant] = []
    
    activeParticipants = peerStates?.participants ?? []
//    activeParticipants = activeParticipants.sorted(by: { lhs, rhs in
//
//        let lhsValue = (lhs.activityTimestamp
//                            ?? Double(lhs.joinTimestamp))
//        let rhsValue = (rhs.activityTimestamp
//                            ?? Double(rhs.joinTimestamp))
//        return lhsValue > rhsValue
//    })
    
    if !activeParticipants.contains(where: { $0.peer.id == accountPeerId }) {
        memberDatas.append(PeerGroupCallData(peer: accountPeer, presence: TelegramUserPresence(status: .present(until: Int32.max), lastActivity: 0), state: nil, isSpeaking: false, audioLevel: nil, isInvited: false, isKeyWindow: isKeyWindow, unsyncVolume: unsyncVolumes[accountPeer.id], isRecentActive: false, activeIndex: nil, isPinned: currentDominantSpeakerWithVideo?.0 == accountPeer.id))
    } else {
        var bp:Int = 0
        bp += 1
    }


    var lastActivity:[GroupCallUIState.RecentActive] = previousActive

    var activeIndexes: [PeerId : Int] = previousActiveIndexes

    for value in activeParticipants {
        var audioLevel = audioLevels[value.peer.id]
        var isSpeaking = peerStates?.speakingParticipants.contains(value.peer.id) ?? false
        if accountPeerId == value.peer.id, isMuted {
            audioLevel = nil
            isSpeaking = false
        }
        let lastActive: TimeInterval?
        if isSpeaking {
            if let timestamp = audioLevel?.timestamp {
                lastActive = TimeInterval(timestamp)
            } else {
                lastActive = Date().timeIntervalSince1970
            }
            if activeIndexes[value.peer.id] == nil {
                activeIndexes[value.peer.id] = (activeIndexes.map({ $0.value }).max() ?? -1) + 1
            }
        } else {
            lastActive = nil
            activeIndexes.removeValue(forKey: value.peer.id)
        }



        if let lastActive = lastActive {
            if let index = lastActivity.firstIndex(where: { $0.peerId == value.peer.id }) {
                lastActivity[index] = .init(peerId: value.peer.id, timestamp: lastActive)
            } else {
                lastActivity.append(.init(peerId: value.peer.id, timestamp: lastActive))
            }
        }
        var containsInActive: Bool = false
        if let index = lastActivity.firstIndex(where: { $0.peerId == value.peer.id }) {
            let activity = lastActivity[index]
            if Date().timeIntervalSince1970 - 60 > activity.timestamp {
                lastActivity.remove(at: index)
            } else {
                containsInActive = true
            }
        }
                
        memberDatas.append(PeerGroupCallData(peer: value.peer, presence: nil, state: value, isSpeaking: isSpeaking, audioLevel: audioLevel?.value, isInvited: false, isKeyWindow: isKeyWindow, unsyncVolume: unsyncVolumes[value.peer.id], isRecentActive: containsInActive && !isSpeaking, activeIndex: activeIndexes[value.peer.id], isPinned: currentDominantSpeakerWithVideo?.0 == value.peer.id))
    }
    
    for invited in invitedPeers {
        if !activeParticipants.contains(where: { $0.peer.id == invited.id}) {
            memberDatas.append(PeerGroupCallData(peer: invited, presence: nil, state: nil, isSpeaking: false, audioLevel: nil, isInvited: true, isKeyWindow: isKeyWindow, unsyncVolume: nil, isRecentActive: false, activeIndex: nil, isPinned: false))
        }
    }

    return GroupCallUIState(memberDatas: memberDatas.sorted(by: >), state: state, isMuted: isMuted, summaryState: summaryState, myAudioLevel: audioLevels[accountPeerId]?.value ?? 0, peer: peerViewMainPeer(peerView)!, cachedData: peerView.cachedData as? CachedChannelData, voiceSettings: voiceSettings, isKeyWindow: isKeyWindow, lastActivity: lastActivity, activeIndexes: activeIndexes, currentDominantSpeakerWithVideo: currentDominantSpeakerWithVideo, activeVideoSources: activeVideoSources)
}


private func peerEntries(state: GroupCallUIState, account: Account, arguments: GroupCallUIArguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var index: Int32 = 0
    
    let nameStyle = ControlStyle(font: .normal(.title), foregroundColor: .white)
    
    
    entries.append(.custom(sectionId: 0, index: index, value: .none, identifier: InputDataIdentifier("invite"), equatable: nil, item: { initialSize, stableId in
        return GeneralInteractedRowItem(initialSize, stableId: stableId, name: L10n.voiceChatInviteInviteMembers, nameStyle: nameStyle, type: .none, viewType: GeneralViewType.firstItem.withUpdatedInsets(NSEdgeInsetsMake(12, 16, 12, 0)), action: {
            arguments.inviteMembers()
        }, drawCustomSeparator: true, thumb: GeneralThumbAdditional(thumb: GroupCallTheme.inviteIcon, textInset: 44, thumbInset: 1), border: [.Bottom], inset: NSEdgeInsets(), customTheme: GroupCallTheme.customTheme)
    }))
    index += 1

    var recent: Bool? = nil



    for (i, data) in state.memberDatas.enumerated() {

        var drawLine = i != state.memberDatas.count - 1

        if recent == nil {
            if !data.isSpeaking {
                if !state.memberDatas.contains (where: { $0.isRecentActive }) && state.memberDatas.contains (where: { $0.isSpeaking }) {
                    recent = false
                }
            }
        }


        var viewType: GeneralViewType = bestGeneralViewType(state.memberDatas, for: i)
        if i == 0 {
            viewType = i != state.memberDatas.count - 1 ? .innerItem : .lastItem
        }
        let separatorTheme = GeneralRowItem.Theme(grayBackground: GroupCallTheme.membersColor.darker(), grayTextColor: GroupCallTheme.grayStatusColor)
        
        if state.memberDatas.count > 50 {
            if recent == nil, data.isRecentActive {
                if i < state.memberDatas.count - 2, i > 0 {
                    entries.append(.custom(sectionId: 0, index: index, value: .none, identifier: InputDataIdentifier("recent_active"), equatable: nil, item: { initialSize, stableId in
                        return SeparatorRowItem(initialSize, stableId, string: L10n.voiceChatBlockRecentActive, state: .none, height: 20, leftInset: 10, border: [], customTheme: separatorTheme)
                    }))
                    index += 1
                }
                recent = false
            } else if !data.isRecentActive, recent == false {
                if i < state.memberDatas.count - 2, i > 0 {
                    entries.append(.custom(sectionId: 0, index: index, value: .none, identifier: InputDataIdentifier("listening"), equatable: nil, item: { initialSize, stableId in
                        return SeparatorRowItem(initialSize, stableId, string: L10n.voiceChatBlockListening, state: .none, height: 20, leftInset: 10, border: [], customTheme: separatorTheme)
                    }))
                    index += 1
                }
                recent = true
            }
            if recent == nil, i < state.memberDatas.count - 2, state.memberDatas[i + 1].isRecentActive {
                drawLine = false
            } else if recent == false, i < state.memberDatas.count - 2, !state.memberDatas[i + 1].isRecentActive {
                drawLine = false
            }
        }
       

        struct Tuple : Equatable {
            let drawLine: Bool
            let data: PeerGroupCallData
            let canManageCall:Bool
            let adminIds: Set<PeerId>
            let viewType: GeneralViewType
        }

        let tuple = Tuple(drawLine: drawLine, data: data, canManageCall: state.state.canManageCall, adminIds: state.state.adminIds, viewType: viewType)


        entries.append(.custom(sectionId: 0, index: index, value: .none, identifier: InputDataIdentifier("_peer_id_\(data.peer.id.toInt64())"), equatable: InputDataEquatable(tuple), item: { initialSize, stableId in
            return GroupCallParticipantRowItem(initialSize, stableId: stableId, account: account, data: data, canManageCall: state.state.canManageCall, isInvited: data.isInvited, isLastItem: false, drawLine: drawLine, viewType: viewType, action: {
                
            }, invite: arguments.invite, contextMenu: {
                var items: [ContextMenuItem] = []

                if let state = data.state {
                    
                    if data.peer.id != account.peerId {
                        let volume: ContextMenuItem = .init("Volume", handler: {

                        })

                        let volumeControl = VolumeMenuItemView(frame: NSMakeRect(0, 0, 160, 26))
                        volumeControl.stateImages = (on: NSImage(named: "Icon_VolumeMenu_On")!.precomposed(.white),
                                                     off: NSImage(named: "Icon_VolumeMenu_Off")!.precomposed(.white))
                        volumeControl.value = CGFloat((data.state?.volume ?? 10000)) / 10000.0
                        volumeControl.lineColor = GroupCallTheme.memberSeparatorColor.lighter()
                        volume.view = volumeControl

                        volumeControl.didUpdateValue = { value, sync in
                            arguments.setVolume(data.peer.id, Double(value), sync)
                        }

                        items.append(volume)
                        items.append(ContextSeparatorItem())
                    }
                   // if data.peer.id != account.peerId {
                        if arguments.takeVideo(data.peer.id) != nil {
                            if !arguments.isPinnedVideo(data.peer.id) {
                                items.append(ContextMenuItem(L10n.voiceChatPinVideo, handler: {
                                    if data.peer.id != account.peerId {
                                        arguments.pinVideo(data.peer.id, state.ssrc)
                                    } else {
                                        arguments.pinVideo(data.peer.id, 0)
                                    }
                                }))
                            } else {
                                items.append(ContextMenuItem(L10n.voiceChatUnpinVideo, handler: {
                                    arguments.unpinVideo()
                                }))
                            }
                        }
                  //  }
                    
                    
                    if !tuple.canManageCall, data.peer.id != account.peerId {
                        if let muteState = data.state?.muteState {
                            if muteState.mutedByYou {
                                items.append(.init(L10n.voiceChatUnmuteForMe, handler: {
                                    arguments.mute(data.peer.id, false, data.state?.volume)
                                }))
                            } else {
                                items.append(.init(L10n.voiceChatMuteForMe, handler: {
                                    arguments.mute(data.peer.id, true, data.state?.volume)
                                }))
                            }
                        } else {
                            items.append(.init(L10n.voiceChatMuteForMe, handler: {
                                arguments.mute(data.peer.id, true, data.state?.volume)
                            }))
                        }                        
                        items.append(ContextSeparatorItem())
                    }
                    
                    if tuple.canManageCall, data.peer.id != account.peerId {
                        if tuple.adminIds.contains(data.peer.id) {
                            if data.state?.muteState == nil {
                                items.append(.init(L10n.voiceChatMutePeer, handler: {
                                    arguments.mute(data.peer.id, true, data.state?.volume)
                                }))
                            }
                            if !tuple.adminIds.contains(data.peer.id) {
                                items.append(.init(L10n.voiceChatRemovePeer, handler: {
                                    arguments.remove(data.peer)
                                }))
                            }
                            if !items.isEmpty {
                                items.append(ContextSeparatorItem())
                            }
                        } else if let muteState = data.state?.muteState, !muteState.canUnmute {
                            items.append(.init(L10n.voiceChatUnmutePeer, handler: {
                                arguments.mute(data.peer.id, false, data.state?.volume)
                            }))
                        } else {
                            items.append(.init(L10n.voiceChatMutePeer, handler: {
                                arguments.mute(data.peer.id, true, data.state?.volume)
                            }))
                        }
                        if !tuple.adminIds.contains(data.peer.id) {
                            items.append(.init(L10n.voiceChatRemovePeer, handler: {
                                arguments.remove(data.peer)
                            }))
                        }
                        if !items.isEmpty {
                            items.append(ContextSeparatorItem())
                        }
                    }
                    
                    if data.peer.id != account.peerId {
                        items.append(.init(L10n.voiceChatOpenProfile, handler: {
                            arguments.openInfo(data.peer.id)
                        }))
                    }
                }
                return .single(items)
            }, takeVideo: {
                return arguments.takeVideo(data.peer.id)
            })
        }))
        index += 1

    }
    
    return entries
}



final class GroupCallUIController : ViewController {
    
    struct UIData {
        let call: PresentationGroupCall
        let peerMemberContextsManager: PeerChannelMemberCategoriesContextsManager
        init(call: PresentationGroupCall, peerMemberContextsManager: PeerChannelMemberCategoriesContextsManager) {
            self.call = call
            self.peerMemberContextsManager = peerMemberContextsManager
        }
    }
    private let data: UIData
    private let disposable = MetaDisposable()
    private let pushToTalkDisposable = MetaDisposable()
    private let requestPermissionDisposable = MetaDisposable()
    private let voiceSourcesDisposable = MetaDisposable()
    private var pushToTalk: PushToTalk?
    private let actionsDisposable = DisposableSet()
    private var canManageCall: Bool = false
    private let connecting = MetaDisposable()
    
    private weak var sharing: DesktopCapturerWindow?
    
    private var requestedVideoSources = Set<UInt32>()
    private var videoViews: [(PeerId, UInt32, GroupVideoView)] = []
    private var currentDominantSpeakerWithVideoSignal:Promise<(PeerId, UInt32)?> = Promise(nil)
    private var currentDominantSpeakerWithVideo: (PeerId, UInt32)? {
        didSet {
            currentDominantSpeakerWithVideoSignal.set(.single(currentDominantSpeakerWithVideo))
        }
    }

    
    var disableSounds: Bool = false
    init(_ data: UIData) {
        self.data = data
        super.init()
        bar = .init(height: 0)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let actionsDisposable = self.actionsDisposable
        
        let peerId = self.data.call.peerId
        let account = self.data.call.account

        guard let window = self.navigationController?.window else {
            fatalError()
        }
        
        
        self.pushToTalk = PushToTalk(sharedContext: data.call.sharedContext, window: window)

        let sharedContext = self.data.call.sharedContext
        
        let unsyncVolumes = ValuePromise<[PeerId: Int32]>([:])
        
        let arguments = GroupCallUIArguments(leave: { [weak self] in

            guard let `self` = self, let window = self.window else {
                return
            }
            if self.canManageCall {
                modernConfirm(for: window, account: account, peerId: nil, header: L10n.voiceChatEndTitle, information: L10n.voiceChatEndText, okTitle: L10n.voiceChatEndOK, thridTitle: L10n.voiceChatEndThird, thridAutoOn: false, successHandler: {
                    [weak self] result in
                    _ = self?.data.call.sharedContext.endGroupCall(terminate: result == .thrid).start()
                })
            } else {
                _ = self.data.call.sharedContext.endGroupCall(terminate: false).start()
            }
        }, settings: { [weak self] in
            guard let `self` = self else {
                return
            }
            self.navigationController?.push(GroupCallSettingsController(sharedContext: sharedContext, account: account, call: self.data.call))
        }, invite: { [weak self] peerId in
            self?.data.call.invitePeer(peerId)
        }, mute: { [weak self] peerId, isMuted, volume in
            self?.data.call.updateMuteState(peerId: peerId, isMuted: isMuted, volume: volume)
        }, toggleSpeaker: { [weak self] in
            self?.data.call.toggleIsMuted()
        }, remove: { [weak self] peer in
            guard let window = self?.window else {
                return
            }
            modernConfirm(for: window, account: account, peerId: peer.id, information: L10n.voiceChatRemovePeerConfirm(peer.displayTitle), okTitle: L10n.voiceChatRemovePeerConfirmOK, cancelTitle: L10n.voiceChatRemovePeerConfirmCancel, successHandler: { [weak window] _ in

                if peerId.namespace == Namespaces.Peer.CloudChannel {
                    _ = self?.data.peerMemberContextsManager.updateMemberBannedRights(account: account, peerId: peerId, memberId: peer.id, bannedRights: TelegramChatBannedRights(flags: [.banReadMessages], untilDate: 0)).start()
                } else if let window = window {
                    _ = showModalProgress(signal: removePeerMember(account: account, peerId: peerId, memberId: peer.id), for: window).start()
                }

            }, appearance: darkPalette.appearance)
        }, openInfo: { peerId in
            appDelegate?.navigateProfile(peerId, account: account)
        }, inviteMembers: { [weak self] in
            guard let window = self?.window, let data = self?.data else {
                return
            }
            
            actionsDisposable.add(GroupCallAddmembers(data, window: window).start(next: { [weak window, weak self] peerId in
                if let peerId = peerId.first, let window = window {
                    self?.data.call.invitePeer(peerId)
                    _ = showModalSuccess(for: window, icon: theme.icons.successModalProgress, delay: 2.0).start()
                }
            }))
                
        }, shareSource: { [weak self] in
            self?.sharing = presentDesktopCapturerWindow(select: { [weak self] source in
                self?.data.call.requestVideo(deviceId: source.deviceIdKey())
            }, devices: sharedContext.devicesContext)
        }, takeVideo: { [weak self] peerId in
            return self?.videoViews.first(where: { $0.0 == peerId })?.2
        }, pinVideo: { [weak self] peerId, ssrc in
            self?.currentDominantSpeakerWithVideo = (peerId, ssrc)
            self?.data.call.setFullSizeVideo(peerId: peerId)
        }, unpinVideo: { [weak self]  in
            self?.currentDominantSpeakerWithVideo = nil
            self?.data.call.setFullSizeVideo(peerId: nil)
        }, isPinnedVideo: { [weak self] peerId in
            return self?.currentDominantSpeakerWithVideo?.0 == peerId
        }, setVolume: { [weak self] peerId, volume, sync in
            let value = Int32(volume * 10000)
            self?.data.call.setVolume(peerId: peerId, volume: value, sync: sync)
            if sync {
                unsyncVolumes.set([:])
            } else {
                unsyncVolumes.set([peerId : value])
            }
        }, getAccountPeerId:{ [weak self] in
            return self?.data.call.account.peerId
        }, cancelSharing: { [weak self] in
            self?.data.call.disableVideo()
        })
        
        genericView.arguments = arguments
        
        self.voiceSourcesDisposable.set((self.data.call.incomingVideoSources |> deliverOnMainQueue).start(next: { [weak self] sources in
                    guard let strongSelf = self else {
                        return
                    }
                    var updated = false
                    var validSources = Set<UInt32>()
                    for (peerId, source) in sources {
                        validSources.insert(source)
                        if !strongSelf.requestedVideoSources.contains(source) {
                            strongSelf.requestedVideoSources.insert(source)
                            strongSelf.data.call.makeVideoView(source: source, completion: { videoView in
                                Queue.mainQueue().async {
                                    guard let strongSelf = self, let videoView = videoView else {
                                        return
                                    }
                                    let videoViewValue = GroupVideoView(videoView: videoView)
                                    strongSelf.videoViews.append((peerId, source, videoViewValue))
                                    strongSelf.genericView.peersTable.enumerateItems(with: { item in
                                        item.redraw(animated: true)
                                        return true
                                    })
                                }
                            })
                        }
                    }

                    for i in (0 ..< strongSelf.videoViews.count).reversed() {
                        if !validSources.contains(strongSelf.videoViews[i].1) {
                            let ssrc = strongSelf.videoViews[i].1
                            strongSelf.videoViews.remove(at: i)
                            strongSelf.requestedVideoSources.remove(ssrc)
                            updated = true
                       }
                   }

                    if let (_, source) = strongSelf.currentDominantSpeakerWithVideo {
                        if !validSources.contains(source) {
                            strongSelf.currentDominantSpeakerWithVideo = nil
                            strongSelf.data.call.setFullSizeVideo(peerId: nil)
                           //strongSelf.mainVideoContainer.updatePeer(peer: nil)
                        }
                    }

                    if updated {
                        strongSelf.genericView.peersTable.enumerateItems(with: { item in
                            item.redraw(animated: true)
                            return true
                        })
                    }
                }))

        
        
        let members: Signal<PresentationGroupCallMembers?, NoError> = self.data.call.members
        let cachedAudioValues:Atomic<[PeerId: PeerGroupCallData.AudioLevel]> = Atomic(value: [:])

        let audioLevels: Signal<[PeerId : PeerGroupCallData.AudioLevel], NoError> = .single([:]) |> then(.single([]) |> then(self.data.call.audioLevels) |> map { values in
            return cachedAudioValues.modify { list in
                var list = list.filter { level in
                    return values.contains(where: { $0.0 == level.key })
                }
                for value in values {
                    var updated: Bool = true
                    if let listValue = list[value.0] {
                        if listValue.value == value.1 {
                            updated = false
                        }
                    }
                    if updated {
                        list[value.0] = PeerGroupCallData.AudioLevel(timestamp: Int32(Date().timeIntervalSince1970), value: value.1)
                    }
                }
                return list
            }
        })

        let animate: Signal<Bool, NoError> = window.takeOcclusionState |> map {
            $0.contains(.visible)
        }
        
        let invited: Signal<[Peer], NoError> = self.data.call.invitedPeers |> mapToSignal { ids in
            return account.postbox.transaction { transaction -> [Peer] in
                var peers:[Peer] = []
                for id in ids {
                    if let peer = transaction.getPeer(id) {
                        peers.append(peer)
                    }
                }
                return peers
            }
        }
        
               
        let queue = Queue(name: "voicechat.ui")

        
        let some = combineLatest(queue: queue, self.data.call.isMuted, animate, account.postbox.loadedPeerWithId(account.peerId), unsyncVolumes.get(), currentDominantSpeakerWithVideoSignal.get(), self.data.call.incomingVideoSources)

        let previousActive: Atomic<[GroupCallUIState.RecentActive]> = Atomic(value: [])
        let previousActiveIndexes:Atomic<[PeerId: Int]> = Atomic(value: [:])

        let state: Signal<GroupCallUIState, NoError> = combineLatest(queue: queue, self.data.call.state, members, audioLevels, account.viewTracker.peerView(peerId), invited, self.data.call.summaryState, voiceCallSettings(data.call.sharedContext.accountManager), some) |> mapToQueue { values in

            let state = makeState(previousActive: previousActive.with { $0 },
                                previousActiveIndexes: previousActiveIndexes.with { $0 },
                                peerView: values.3,
                                state: values.0,
                                isMuted: values.7.0,
                                invitedPeers: values.4,
                                peerStates: values.1,
                                audioLevels: values.2,
                                summaryState: values.5,
                                voiceSettings: values.6,
                                isKeyWindow: values.7.1,
                                accountPeer: values.7.2,
                                unsyncVolumes: values.7.3,
                                currentDominantSpeakerWithVideo: values.7.4,
                                activeVideoSources: values.7.5)

            _ = previousActive.swap(state.lastActivity)
            _ = previousActiveIndexes.swap(state.activeIndexes)
            return .single(state)
        } |> distinctUntilChanged

        
        let initialSize = NSMakeSize(340, 360)
        let previousEntries:Atomic<[AppearanceWrapperEntry<InputDataEntry>]> = Atomic(value: [])
        let animated: Atomic<Bool> = Atomic(value: false)
        let inputArguments = InputDataArguments(select: { _, _ in }, dataUpdated: {})
        
        let transition: Signal<(GroupCallUIState, TableUpdateTransition), NoError> = combineLatest(state, appearanceSignal) |> mapToQueue { state, appAppearance in
            let current = peerEntries(state: state, account: account, arguments: arguments).map { AppearanceWrapperEntry(entry: $0, appearance: appAppearance) }
            return prepareInputDataTransition(left: previousEntries.swap(current), right: current, animated: state.isKeyWindow, searchState: nil, initialSize: initialSize, arguments: inputArguments, onMainQueue: false) |> map {
                (state, $0)
            }
        } |> deliverOnMainQueue
        
        self.disposable.set(transition.start { [weak self] value in
            guard let strongSelf = self else {
                return
            }
            strongSelf.applyUpdates(value.0, value.1, strongSelf.data.call, animated: animated.swap(true))
            strongSelf.readyOnce()
        })
        

        self.onDeinit = {
            _ = previousActive.modify { _ in
                return []
            }
        }

        genericView.peersTable.setScrollHandler { [weak self] position in
            switch position.direction {
            case .bottom:
                self?.data.call.loadMore()
            default:
                break
            }
        }

        var connectedMusicPlayed: Bool = false
        
        let connecting = self.connecting
                
        pushToTalkDisposable.set(combineLatest(queue: .mainQueue(), data.call.state, data.call.isMuted, data.call.canBeRemoved).start(next: { [weak self] state, isMuted, canBeRemoved in
            
            let disableSounds = self?.disableSounds ?? true
            
            switch state.networkState {
            case .connected:
                if !connectedMusicPlayed && !disableSounds {
                    SoundEffectPlay.play(postbox: account.postbox, name: "call up")
                    connectedMusicPlayed = true
                }
                if canBeRemoved, connectedMusicPlayed  && !disableSounds {
                    SoundEffectPlay.play(postbox: account.postbox, name: "call down")
                }
                connecting.set(nil)
            case .connecting:
                connecting.set((Signal<Void, NoError>.single(Void()) |> delay(3.0, queue: .mainQueue()) |> restart).start(next: {
                    SoundEffectPlay.play(postbox: account.postbox, name: "reconnecting")
                }))
            }

            self?.pushToTalk?.update = { [weak self] mode in
                switch state.networkState {
                case .connected:
                    switch mode {
                    case .speaking:
                        if isMuted {
                            if let muteState = state.muteState {
                                if muteState.canUnmute {
                                    self?.data.call.setIsMuted(action: .muted(isPushToTalkActive: true))
                                    self?.pushToTalkIsActive = true
                                }
                            }
                        }
                    case .waiting:
                        if !isMuted, self?.pushToTalkIsActive == true {
                            self?.data.call.setIsMuted(action: .muted(isPushToTalkActive: false))
                        }
                        self?.pushToTalkIsActive = false
                    case .toggle:
                        if let muteState = state.muteState {
                            if muteState.canUnmute {
                                self?.data.call.setIsMuted(action: .unmuted)
                            }
                        } else {
                            self?.data.call.setIsMuted(action: .muted(isPushToTalkActive: false))
                        }
                    }
                case .connecting:
                    break
                }
            }
        }))
        
        var hasMicroPermission: Bool? = nil
        
        let alertPermission = { [weak self] in
            guard let window = self?.window else {
                return
            }
            confirm(for: window, information: L10n.voiceChatRequestAccess, okTitle: L10n.modalOK, cancelTitle: "", thridTitle: L10n.requestAccesErrorConirmSettings, successHandler: { result in
                switch result {
                case .thrid:
                    openSystemSettings(.microphone)
                default:
                    break
                }
            }, appearance: darkPalette.appearance)
        }
        
        data.call.permissions = { action, f in
            switch action {
            case .unmuted, .muted(isPushToTalkActive: true):
                if let permission = hasMicroPermission {
                    f(permission)
                    if !permission {
                        alertPermission()
                    }
                } else {
                    _ = requestMicrophonePermission().start(next: { permission in
                        hasMicroPermission = permission
                        f(permission)
                        if !permission {
                            alertPermission()
                        }
                    })
                }
            default:
                f(true)
            }
        }
        
    }
    
    override func readyOnce() {
        let was = self.didSetReady
        super.readyOnce()
        if didSetReady, !was {
            requestPermissionDisposable.set(requestMicrophonePermission().start())
        }
    }
    
    private var pushToTalkIsActive: Bool = false
    
    private func applyUpdates(_ state: GroupCallUIState, _ transition: TableUpdateTransition, _ call: PresentationGroupCall, animated: Bool) {
        self.genericView.applyUpdates(state, transition, call, animated: animated)
        canManageCall = state.state.canManageCall
    }
    
    deinit {
        disposable.dispose()
        pushToTalkDisposable.dispose()
        requestPermissionDisposable.dispose()
        actionsDisposable.dispose()
        connecting.dispose()
        sharing?.orderOut(nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    private var genericView: GroupCallView {
        return self.view as! GroupCallView
    }
    
    
    override func viewClass() -> AnyClass {
        return GroupCallView.self
    }
}
