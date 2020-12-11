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
    let mute:(PeerId, Bool)->Void
    let toggleSpeaker:()->Void
    let remove:(Peer)->Void
    let openInfo: (PeerId)->Void
    init(leave:@escaping()->Void,
    settings:@escaping()->Void,
    invite:@escaping(PeerId)->Void,
    mute:@escaping(PeerId, Bool)->Void,
    toggleSpeaker:@escaping()->Void,
    remove:@escaping(Peer)->Void,
    openInfo: @escaping(PeerId)->Void) {
        self.leave = leave
        self.invite = invite
        self.mute = mute
        self.settings = settings
        self.toggleSpeaker = toggleSpeaker
        self.remove = remove
        self.openInfo = openInfo
    }
}

private final class GroupCallControlsView : View {
    private let speak: GroupCallSpeakButton = GroupCallSpeakButton(frame: NSMakeRect(0, 0, 144, 144))
    private let settings: CallControl = CallControl(frame: .zero)
    private let end: CallControl = CallControl(frame: .zero)
    private var speakText: TextView?
    fileprivate var arguments: GroupCallUIArguments?
    private let playbackAudioLevelView: VoiceBlobView

    private let foregroundView = View()
    private let foregroundGradientLayer = CAGradientLayer()

    private let maskView = View()
    private let maskGradientLayer = CAGradientLayer()
    private let maskCircleLayer = CAShapeLayer()




    required init(frame frameRect: NSRect) {
        playbackAudioLevelView = VoiceBlobView(
            frame: NSMakeRect(0, 0, 220, 220),
            maxLevel: 0.3,
            smallBlobRange: (0, 0),
            mediumBlobRange: (0.7, 0.8),
            bigBlobRange: (0.8, 0.9)
        )

        super.init(frame: frameRect)
     //   addSubview(foregroundView)
        addSubview(playbackAudioLevelView)
        addSubview(speak)
        addSubview(settings)
        addSubview(end)

        
        end.set(handler: { [weak self] _ in
            self?.arguments?.leave()
        }, for: .Click)
        
        settings.set(handler: { [weak self] _ in
            self?.arguments?.settings()
        }, for: .Click)
        
        speak.set(handler: { [weak self] _ in
            self?.arguments?.toggleSpeaker()
        }, for: .Click)
        

//
//        self.foregroundGradientLayer.type = .radial
//        self.foregroundGradientLayer.colors = [lightBlue.cgColor, blue.cgColor]
//        self.foregroundGradientLayer.startPoint = CGPoint(x: 1.0, y: 0.0)
//        self.foregroundGradientLayer.endPoint = CGPoint(x: 0.0, y: 1.0)
//
//        self.maskView.backgroundColor = .clear
//
//
//
//        self.maskGradientLayer.type = .radial
//        self.maskGradientLayer.colors = [NSColor(rgb: 0xffffff, alpha: 0.4).cgColor, NSColor(rgb: 0xffffff, alpha: 0.0).cgColor]
//        self.maskGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
//        self.maskGradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
//        self.maskGradientLayer.transform = CATransform3DMakeScale(0.3, 0.3, 1.0)
//        self.maskGradientLayer.isHidden = false
//
//        let largerCirclePath = CGMutablePath()
//        largerCirclePath.addEllipse(in: NSMakeRect(0, 0, bounds.height - 20, bounds.height - 20))
//        self.maskCircleLayer.fillColor = NSColor.white.cgColor
//        self.maskCircleLayer.path = largerCirclePath
//        self.maskCircleLayer.isHidden = false
//
//
//
//        self.foregroundView.layer?.mask = self.maskView.layer
//        self.foregroundView.layer?.addSublayer(self.foregroundGradientLayer)
//
//
//        self.maskView.layer?.addSublayer(self.maskGradientLayer)
//        self.maskView.layer?.addSublayer(self.maskCircleLayer)


    }
    
    private var preiousState: PresentationGroupCallState?
    
    func update(_ callState: GroupCallUIState, voiceSettings: VoiceCallSettings, audioLevel: Float?, animated: Bool) {
        
        let state = callState.state
        speak.update(with: state, isMuted: callState.isMuted, audioLevel: audioLevel, animated: animated)
        
        switch state.networkState {
        case .connecting:
            playbackAudioLevelView.change(opacity: 0, animated: animated)
            playbackAudioLevelView.setColor(GroupCallTheme.speakDisabledColor)
            playbackAudioLevelView.stopAnimating()
        case .connected:
            if callState.isMuted {
                if let muteState = state.muteState {
                    if muteState.canUnmute {
                        playbackAudioLevelView.setColor(GroupCallTheme.speakInactiveColor)
                    } else {
                        playbackAudioLevelView.setColor(GroupCallTheme.speakDisabledColor)
                    }
                } else {
                    playbackAudioLevelView.updateLevel(CGFloat(audioLevel ?? 0))
                    playbackAudioLevelView.setColor(GroupCallTheme.speakActiveColor)
                }
            } else {
                playbackAudioLevelView.updateLevel(CGFloat(audioLevel ?? 0))
                playbackAudioLevelView.setColor(GroupCallTheme.speakActiveColor)
            }
            if callState.isMuted {
                if let muteState = state.muteState {
                    if muteState.canUnmute {
                        playbackAudioLevelView.change(opacity: 1, animated: animated)
                    } else {
                        playbackAudioLevelView.change(opacity: 0, animated: animated)
                    }
                } else {
                    playbackAudioLevelView.change(opacity: 1, animated: animated)
                }
            } else {
                playbackAudioLevelView.change(opacity: 1, animated: animated)
            }
            
        }
        
        if callState.isKeyWindow {
            playbackAudioLevelView.startAnimating()
        } else {
            playbackAudioLevelView.stopAnimating()
            playbackAudioLevelView.change(opacity: 0, animated: animated)
        }
        
        if state != preiousState {
            
            end.updateWithData(CallControlData(text: L10n.voiceChatLeave, isVisualEffect: false, icon: GroupCallTheme.declineIcon, iconSize: NSMakeSize(60, 60), backgroundColor: GroupCallTheme.declineColor), animated: animated)

            settings.updateWithData(CallControlData(text: L10n.voiceChatSettings, isVisualEffect: false, icon: GroupCallTheme.settingsIcon, iconSize: NSMakeSize(60, 60), backgroundColor: GroupCallTheme.settingsColor), animated: animated)

        }

        let statusText: String
        var secondary: String? = nil
        switch state.networkState {
        case .connected:
            if callState.isMuted {
                if let muteState = state.muteState {
                    if muteState.canUnmute {
                        statusText = L10n.voiceChatClickToUnmute
                        if let pushToTalk = voiceSettings.pushToTalk {
                            switch voiceSettings.mode {
                            case .always:
                                secondary = L10n.voiceChatClickToUnmuteSecondaryPress(pushToTalk.string)
                            case .pushToTalk:
                                secondary = L10n.voiceChatClickToUnmuteSecondaryHold(pushToTalk.string)
                            case .none:
                                secondary = nil
                            }
                        }
                    } else {
                        statusText = L10n.voiceChatListenMode
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
                    speakText.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak speakText] _ in
                        speakText?.removeFromSuperview()
                    })
                    speakText.layer?.animateScaleSpring(from: 1, to: 0.2, duration: 0.2)
                } else {
                    speakText.removeFromSuperview()
                }
            }


            self.speakText = speakText
            addSubview(speakText)
            speakText.centerX(y: speak.frame.maxY + floorToScreenPixels(backingScaleFactor, ((frame.height - speak.frame.maxY) - speakText.frame.height) / 2))
            if animated {
                speakText.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                speakText.layer?.animateScaleSpring(from: 0.2, to: 1, duration: 0.2)
            }
        }

        self.preiousState = state
        needsLayout = true

        //updateGlowAndGradientAnimations(active: nil)

    }
    
    override var mouseDownCanMoveWindow: Bool {
        return true
    }

    private func setupGradientAnimations() {
        if let _ = self.foregroundGradientLayer.animation(forKey: "movement") {
        } else {
            let previousValue = self.foregroundGradientLayer.startPoint
            let newValue: CGPoint
//            if self.maskBlobView.presentationAudioLevel > 0.15 {
//                newValue = CGPoint(x: CGFloat.random(in: 0.8 ..< 1.0), y: CGFloat.random(in: 0.1 ..< 0.45))
//            } else {
                newValue = CGPoint(x: CGFloat.random(in: 0.6 ..< 0.8), y: CGFloat.random(in: 0.1 ..< 0.45))
//            }
            self.foregroundGradientLayer.startPoint = newValue

            CATransaction.begin()

            let animation = CABasicAnimation(keyPath: "startPoint")
            animation.duration = Double.random(in: 0.8 ..< 1.4)
            animation.fromValue = previousValue
            animation.toValue = newValue

            CATransaction.setCompletionBlock { [weak self] in
                self?.setupGradientAnimations()
            }

            self.foregroundGradientLayer.add(animation, forKey: "movement")
            CATransaction.commit()
        }
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


    func updateGlowAndGradientAnimations(active: Bool?, previousActive: Bool? = nil) {
        let effectivePreviousActive = previousActive ?? false

        let initialScale: CGFloat = ((self.maskGradientLayer.value(forKeyPath: "presentationLayer.transform.scale.x") as? NSNumber)?.floatValue).flatMap({ CGFloat($0) }) ?? (((self.maskGradientLayer.value(forKeyPath: "transform.scale.x") as? NSNumber)?.floatValue).flatMap({ CGFloat($0) }) ?? (effectivePreviousActive ? 0.95 : 0.8))
        let initialColors = self.foregroundGradientLayer.colors

        let outerColor: NSColor?
        let targetColors: [CGColor]
        let targetScale: CGFloat
        if let active = active {
            if active {
                targetColors = [blue.cgColor, green.cgColor]
                targetScale = 0.89
                outerColor = NSColor(rgb: 0x005720)
            } else {
                targetColors = [lightBlue.cgColor, blue.cgColor]
                targetScale = 0.85
                outerColor = NSColor(rgb: 0x00274d)
            }
        } else {
            targetColors = [lightBlue.cgColor, blue.cgColor]
            targetScale = 0.3
            outerColor = nil
        }

        self.maskGradientLayer.transform = CATransform3DMakeScale(targetScale, targetScale, 1.0)
        if let _ = previousActive {
            self.maskGradientLayer.animateScale(from: initialScale, to: targetScale, duration: 0.3)
        } else {
            self.maskGradientLayer.animateSpring(from: initialScale as NSNumber, to: targetScale as NSNumber, keyPath: "transform.scale", duration: 0.45)
        }

        self.foregroundGradientLayer.colors = targetColors
        self.foregroundGradientLayer.animate(from: initialColors as AnyObject, to: targetColors as AnyObject, keyPath: "colors", timingFunction: .linear, duration: 0.3)
    }


    
    override func layout() {
        super.layout()
        speak.center()
        speak.setFrameOrigin(NSMakePoint(speak.frame.minX, speak.frame.minY - 10))
        playbackAudioLevelView.center()
        playbackAudioLevelView.setFrameOrigin(NSMakePoint(playbackAudioLevelView.frame.minX, playbackAudioLevelView.frame.minY - 10))

        settings.centerY(x: 60)
        end.centerY(x: frame.width - end.frame.width - 60)
        if let speakText = speakText {
            speakText.centerX(y: speak.frame.maxY + floorToScreenPixels(backingScaleFactor, ((frame.height - speak.frame.maxY) - speakText.frame.height) / 2))
        }

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class GroupCallTitleView : View {
    fileprivate let titleView: TextView = TextView()
    fileprivate let statusView: TextView = TextView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(titleView)
        addSubview(statusView)
        titleView.isSelectable = false
        statusView.isSelectable = false
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
    
    
    func update(_ peer: Peer, _ state: GroupCallUIState) {
        let layout = TextViewLayout(.initialize(string: peer.displayTitle, color: GroupCallTheme.titleColor, font: .medium(.title)), maximumNumberOfLines: 1)
        layout.measure(width: frame.width - 100)
        titleView.update(layout)

        let status: String
        if let summaryState = state.summaryState {
            status = L10n.voiceChatStatusMembersCountable(summaryState.participantCount)
        } else {
            status = L10n.voiceChatStatusLoading
        }
        let statusLayout = TextViewLayout.init(.initialize(string: status, color: GroupCallTheme.grayStatusColor, font: .normal(.text)), maximumNumberOfLines: 1)
        statusLayout.measure(width: frame.width - 100)
        statusView.update(statusLayout)
        needsLayout = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class GroupCallView : View {
    let peersTable: TableView = TableView(frame: NSMakeRect(0, 0, 440, 360))
    let titleView: GroupCallTitleView = GroupCallTitleView(frame: NSMakeRect(0, 0, 480, 54))
    private let peersTableContainer: View = View(frame: NSMakeRect(0, 0, 440, 360))
    private let controlsContainer = GroupCallControlsView(frame: .init(x: 0, y: 0, width: 480, height: 640 - 360 - 54))
    
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
        addSubview(peersTableContainer)
        addSubview(titleView)
        addSubview(controlsContainer)
        peersTableContainer.layer?.cornerRadius = 10
        peersTableContainer.addSubview(peersTable)
        updateLocalizationAndTheme(theme: theme)
    }
    
    override var mouseDownCanMoveWindow: Bool {
        return true
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        peersTable.background = GroupCallTheme.membersColor
        backgroundColor = GroupCallTheme.windowBackground
        titleView.backgroundColor = GroupCallTheme.windowBackground
    }
    
    override func layout() {
        super.layout()
        peersTableContainer.centerX(y: 54)
        controlsContainer.centerX(y: peersTableContainer.frame.maxY)
    }
    
    func applyUpdates(_ state: GroupCallUIState, _ transition: TableUpdateTransition, animated: Bool) {
        peersTable.merge(with: transition)
        titleView.update(state.peer, state)
        controlsContainer.update(state, voiceSettings: state.voiceSettings, audioLevel: state.myAudioLevel, animated: animated)
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
    private var weight: Int {
        var weight: Int = 0
        
        if let _ = state {
            if isSpeaking {
                weight += (1 << 30)
            } else {
                weight += (1 << 29)
            }
        } else {
            if let presence = presence {
                switch presence.status {
                case let .present(until):
                    weight += (1 << 28)
                case .recently:
                    weight += (1 << 27)
                case .lastWeek:
                    weight += (1 << 26)
                case .lastMonth:
                    weight += (1 << 25)
                case .none:
                    weight += (1 << 24)
                }
            }
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
        return true
    }
    
    static func <(lhs: PeerGroupCallData, rhs: PeerGroupCallData) -> Bool {
        return lhs.weight < rhs.weight
    }
}


private final class GroupCallUIState : Equatable {
    let memberDatas:[PeerGroupCallData]
    let isMuted: Bool
    let state: PresentationGroupCallState
    let summaryState: PresentationGroupCallSummaryState?
    let peer: Peer
    let cachedData: CachedChannelData?
    let myAudioLevel: Float
    let voiceSettings: VoiceCallSettings
    let isKeyWindow: Bool
    init(memberDatas: [PeerGroupCallData], state: PresentationGroupCallState, isMuted: Bool, summaryState: PresentationGroupCallSummaryState?, myAudioLevel: Float, peer: Peer, cachedData: CachedChannelData?, voiceSettings: VoiceCallSettings, isKeyWindow: Bool) {
        self.summaryState = summaryState
        self.memberDatas = memberDatas
        self.peer = peer
        self.isMuted = isMuted
        self.cachedData = cachedData
        self.state = state
        self.myAudioLevel = myAudioLevel
        self.voiceSettings = voiceSettings
        self.isKeyWindow = isKeyWindow
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
        return true
    }
}

private func makeState(_ peerView: PeerView, _ state: PresentationGroupCallState, _ isMuted: Bool, _ participants: [RenderedChannelParticipant], _ peerStates: PresentationGroupCallMembers?, _ audioLevels: [PeerId : PeerGroupCallData.AudioLevel], _ invitedPeers: Set<PeerId>, _ summaryState: PresentationGroupCallSummaryState?, _ voiceSettings: VoiceCallSettings, _ isKeyWindow: Bool, _ accountPeer: Peer) -> GroupCallUIState {
    
    var memberDatas: [PeerGroupCallData] = []
    
    let accountPeerId = accountPeer.id
    
    var activeParticipants: [GroupCallParticipantsContext.Participant] = []
    
    activeParticipants = peerStates?.participants ?? []
    activeParticipants = activeParticipants.sorted(by: { lhs, rhs in

        let lhsLevel = audioLevels[lhs.peer.id]?.timestamp != nil ? Double(audioLevels[lhs.peer.id]!.timestamp) : nil
        let rhsLevel = audioLevels[rhs.peer.id]?.timestamp != nil ? Double(audioLevels[rhs.peer.id]!.timestamp) : nil

        let lhsValue = (lhsLevel ?? lhs.activityTimestamp
                            ?? Double(lhs.joinTimestamp))
        let rhsValue = (rhsLevel ?? rhs.activityTimestamp
                            ?? Double(rhs.joinTimestamp))
        return lhsValue > rhsValue
    })
    
    if !activeParticipants.contains(where: { $0.peer.id == accountPeerId }) {
        memberDatas.append(PeerGroupCallData(peer: accountPeer, presence: TelegramUserPresence(status: .present(until: Int32.max), lastActivity: 0), state: nil, isSpeaking: false, audioLevel: nil, isInvited: false, isKeyWindow: isKeyWindow))
    }


    
    for value in activeParticipants {
        var audioLevel = audioLevels[value.peer.id]
        if accountPeerId == value.peer.id, isMuted {
            audioLevel = nil
        }

        memberDatas.append(PeerGroupCallData(peer: value.peer, presence: nil, state: value, isSpeaking: peerStates?.speakingParticipants.contains(value.peer.id) ?? false, audioLevel: audioLevel?.value, isInvited: invitedPeers.contains(value.peer.id), isKeyWindow: isKeyWindow))
    }
    
    

    for participant in participants {
        if !activeParticipants.contains(where: { $0.peer.id == participant.peer.id}) {
            if participant.peer.id != accountPeerId {
                memberDatas.append(PeerGroupCallData(peer: participant.peer, presence: participant.presences[participant.peer.id] as? TelegramUserPresence, state: nil, isSpeaking: false, audioLevel: nil, isInvited: invitedPeers.contains(participant.peer.id), isKeyWindow: isKeyWindow))
            }
        }
    }

    return GroupCallUIState(memberDatas: memberDatas.sorted(by: >), state: state, isMuted: isMuted, summaryState: summaryState, myAudioLevel: audioLevels[accountPeerId]?.value ?? 0, peer: peerViewMainPeer(peerView)!, cachedData: peerView.cachedData as? CachedChannelData, voiceSettings: voiceSettings, isKeyWindow: isKeyWindow)
}


private func peerEntries(state: GroupCallUIState, account: Account, arguments: GroupCallUIArguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var index: Int32 = 0
    
    var addedSeparator: Bool = false
    for (i, data) in state.memberDatas.enumerated() {
        
        if data.state == nil, !addedSeparator && data.peer.id != account.peerId {
            entries.append(.custom(sectionId: 0, index: index, value: .none, identifier: .init("separator"), equatable: nil, item: { initialSize, stableId in
                return SeparatorRowItem(initialSize, stableId, string: L10n.voiceChatGroupMembers, height: 20, backgroundColor: GroupCallTheme.memberSeparatorColor, leftInset: 12, border: [])
            }))
            addedSeparator = true

        }
        var nextForeigner = false
        if (data.state != nil || data.peer.id == account.peerId), i < state.memberDatas.count - 1 {
            if state.memberDatas[i + 1].state == nil {
                nextForeigner = true
            }
        }

        struct Tuple : Equatable {
            let nextForeigner: Bool
            let data: PeerGroupCallData
            let canManageCall:Bool
            let adminIds: Set<PeerId>
        }

        let tuple = Tuple(nextForeigner: nextForeigner, data: data, canManageCall: state.state.canManageCall, adminIds: state.state.adminIds)


        entries.append(.custom(sectionId: 0, index: index, value: .none, identifier: InputDataIdentifier("_peer_id_\(data.peer.id.toInt64())"), equatable: InputDataEquatable(tuple), item: { initialSize, stableId in
            return GroupCallParticipantRowItem(initialSize, stableId: stableId, account: account, data: data, canManageCall: state.state.canManageCall, isInvited: data.isInvited, isLastItem: i == state.memberDatas.count - 1, drawLine: !nextForeigner, action: {
                
            }, invite: arguments.invite, mute: arguments.mute, contextMenu: {
                var items: [ContextMenuItem] = []
                
                if tuple.canManageCall, data.peer.id != account.peerId {
                    if tuple.adminIds.contains(data.peer.id) {
                        if data.state?.muteState == nil {
                            items.append(.init(L10n.voiceChatMutePeer, handler: {
                                arguments.mute(data.peer.id, true)
                            }))
                        }
                    } else if let muteState = data.state?.muteState, !muteState.canUnmute {
                        items.append(.init(L10n.voiceChatUnmutePeer, handler: {
                            arguments.mute(data.peer.id, false)
                        }))
                    } else {
                        items.append(.init(L10n.voiceChatMutePeer, handler: {
                            arguments.mute(data.peer.id, true)
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

                return .single(items)
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
    private let actionsDisposable = DisposableSet()
    private let pushToTalkDisposable = MetaDisposable()
    private let requestPermissionDisposable = MetaDisposable()
    private let pushToTalk: PushToTalk

    private var canManageCall: Bool = false

    init(_ data: UIData) {
        self.data = data
        self.pushToTalk = PushToTalk(sharedContext: data.call.sharedContext)
        super.init()
        bar = .init(height: 0)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let peerId = self.data.call.peerId
        let account = self.data.call.account

        guard let window = self.navigationController?.window else {
            fatalError()
        }

        let sharedContext = self.data.call.sharedContext
        
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
        }, mute: { [weak self] peerId, isMuted in
            self?.data.call.updateMuteState(peerId: peerId, isMuted: isMuted)
        }, toggleSpeaker: { [weak self] in
            self?.data.call.toggleIsMuted()
        }, remove: { [weak self] peer in
            guard let window = self?.window else {
                return
            }
            modernConfirm(for: window, account: account, peerId: peer.id, information: L10n.voiceChatRemovePeerConfirm(peer.displayTitle), okTitle: L10n.voiceChatRemovePeerConfirmOK, cancelTitle: L10n.voiceChatRemovePeerConfirmCancel, successHandler: { _ in
                _ = self?.data.peerMemberContextsManager.updateMemberBannedRights(account: account, peerId: peerId, memberId: peer.id, bannedRights: TelegramChatBannedRights(flags: [.banReadMessages], untilDate: 0)).start()
            }, appearance: darkPalette.appearance)
        }, openInfo: { peerId in
            appDelegate?.navigateProfile(peerId, account: account)
        })
        
        genericView.arguments = arguments
        
        var loadMoreControl: PeerChannelMemberCategoryControl?
        
        let channelMembersPromise = Promise<[RenderedChannelParticipant]>()
        let (disposable, control) = data.peerMemberContextsManager.recent(postbox: data.call.account.postbox, network: data.call.account.network, accountPeerId: data.call.peerId, peerId: data.call.peerId, updated: { state in
            channelMembersPromise.set(.single(state.list.filter { $0.peer.isUser && !$0.peer.isBot && !$0.peer.isDeleted }))
        })
        loadMoreControl = control
        actionsDisposable.add(disposable)
        
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
               
        let state: Signal<GroupCallUIState, NoError> = combineLatest(queue: Queue(name: "voicechat.ui"), self.data.call.state, members, .single([]) |> then(channelMembersPromise.get()), audioLevels, account.viewTracker.peerView(peerId), self.data.call.invitedPeers, self.data.call.summaryState, voiceCallSettings(data.call.sharedContext.accountManager), self.data.call.isMuted, animate, account.postbox.loadedPeerWithId(account.peerId)) |> mapToQueue { values in
            return .single(makeState(values.4, values.0, values.8, values.2, values.1, values.3, values.5, values.6, values.7, values.9, values.10))
        } |> distinctUntilChanged
        
        
        let initialSize = NSMakeSize(440, 360)
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
            self?.applyUpdates(value.0, value.1, animated: animated.swap(true))
            self?.readyOnce()
        })
        
        
        genericView.peersTable.setScrollHandler { [weak self] position in
            switch position.direction {
            case .bottom:
                break
            default:
                break
            }
        }

        var connectedMusicPlayed: Bool = false
        
        pushToTalkDisposable.set(combineLatest(queue: .mainQueue(), data.call.state, data.call.isMuted, data.call.canBeRemoved).start(next: { [weak self] state, isMuted, canBeRemoved in

            switch state.networkState {
            case .connected:
                if !connectedMusicPlayed {
                    SoundEffectPlay.play(postbox: account.postbox, name: "interface call up")
                    connectedMusicPlayed = true
                }
                if canBeRemoved, connectedMusicPlayed {
                    SoundEffectPlay.play(postbox: account.postbox, name: "interface call down")
                }
            default:
                break
            }

            self?.pushToTalk.update = { [weak self] mode in
                switch state.networkState {
                case .connected:
                    switch mode {
                    case let .speaking(sound):
                        if isMuted {
                            if let muteState = state.muteState {
                                if muteState.canUnmute {
                                    self?.data.call.setIsMuted(action: .muted(isPushToTalkActive: true))
                                    self?.pushToTalkIsActive = true
                                    SoundEffectPlay.play(postbox: account.postbox, name: sound)
                                }
                            }
                        }
                    case let .waiting(sound):
                        if !isMuted, self?.pushToTalkIsActive == true {
                            self?.data.call.setIsMuted(action: .muted(isPushToTalkActive: false))
                            SoundEffectPlay.play(postbox: account.postbox, name: sound)
                        }
                        self?.pushToTalkIsActive = false
                    case let .toggle(unmuteSound, muteSound):
                        if let muteState = state.muteState {
                            if muteState.canUnmute {
                                self?.data.call.setIsMuted(action: .unmuted)
                                SoundEffectPlay.play(postbox: account.postbox, name: unmuteSound)
                            }
                        } else {
                            self?.data.call.setIsMuted(action: .muted(isPushToTalkActive: false))
                            SoundEffectPlay.play(postbox: account.postbox, name: muteSound)
                        }
                    }
                case .connecting:
                    NSSound.beep()
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
    
    private func applyUpdates(_ state: GroupCallUIState, _ transition: TableUpdateTransition, animated: Bool) {
        self.genericView.applyUpdates(state, transition, animated: animated)
        canManageCall = state.state.canManageCall
    }
    
    deinit {
        disposable.dispose()
        pushToTalkDisposable.dispose()
        actionsDisposable.dispose()
        requestPermissionDisposable.dispose()
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
