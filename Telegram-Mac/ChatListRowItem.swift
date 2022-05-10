//
//  TGDialogRowItem.swift
//  Telegram-Mac
//
//  Created by keepcoder on 07/09/16.
//  Copyright © 2016 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import DateUtils
import SwiftSignalKit
import InAppSettings

enum ChatListPinnedType {
    case some
    case last
    case none
    case ad(AdditionalChatListItem)
}


final class SelectChatListItemPresentation : Equatable {
    let selected:Set<ChatLocation>
    static func ==(lhs:SelectChatListItemPresentation, rhs:SelectChatListItemPresentation) -> Bool {
        return lhs.selected == rhs.selected
    }
    
    init(_ selected:Set<ChatLocation> = Set()) {
        self.selected = selected
    }
    
    func deselect(chatLocation:ChatLocation) -> SelectChatListItemPresentation {
        var chatLocations:Set<ChatLocation> = Set<ChatLocation>()
        chatLocations.formUnion(selected)
        let _ = chatLocations.remove(chatLocation)
        return SelectChatListItemPresentation(chatLocations)
    }
    
    func withToggledSelected(_ chatLocation: ChatLocation) -> SelectChatListItemPresentation {
        var chatLocations:Set<ChatLocation> = Set<ChatLocation>()
        chatLocations.formUnion(selected)
        if chatLocations.contains(chatLocation) {
            let _ = chatLocations.remove(chatLocation)
        } else {
            chatLocations.insert(chatLocation)
        }
        return SelectChatListItemPresentation(chatLocations)
    }
    
}

final class SelectChatListInteraction : InterfaceObserver {
    private(set) var presentation:SelectChatListItemPresentation = SelectChatListItemPresentation()
    
    func update(animated:Bool = true, _ f:(SelectChatListItemPresentation)->SelectChatListItemPresentation)->Void {
        let oldValue = self.presentation
        presentation = f(presentation)
        if oldValue != presentation {
            notifyObservers(value: presentation, oldValue:oldValue, animated:animated)
        }
    }
    
}

enum ChatListRowState : Equatable {
    case plain
    case deletable(onRemove:(ChatLocation)->Void, deletable:Bool)
    
    static func ==(lhs: ChatListRowState, rhs: ChatListRowState) -> Bool {
        switch lhs {
        case .plain:
            if case .plain = rhs {
                return true
            } else {
                return false
            }
        case .deletable(_, let deletable):
            if case .deletable(_, deletable) = rhs {
                return true
            } else {
                return false
            }
        }
    }
}



class ChatListRowItem: TableRowItem {

    struct Badge {
        let dynamicValue: DynamicCounterTextView.Value
        let backgroundColor: NSColor
        let size: NSSize
        init(dynamicValue: DynamicCounterTextView.Value, backgroundColor: NSColor, size: NSSize) {
            self.dynamicValue = dynamicValue
            self.backgroundColor = backgroundColor
            var mapped = NSMakeSize(max(CGFloat(dynamicValue.values.count) * 10 - 10 + 7, size.width + 8), size.height + 7)
            mapped = NSMakeSize(max(mapped.height,mapped.width), mapped.height)
            self.size = mapped
        }
    }
    
    public private(set) var messages:[Message]
    
    var message: Message? {
        var effective: Message?
        
        let filtered = messages.filter { !$0.text.isEmpty }
        if filtered.count == 1 {
            effective = filtered[0]
        }

        if effective == nil {
            effective = messages.first
        }
        return effective
    }
    
    let context: AccountContext
    let peer:Peer?
    let renderedPeer:RenderedPeer?
    let groupId: PeerGroupId
    //let groupUnreadCounters: GroupReferenceUnreadCounters?
    let chatListIndex:ChatListIndex?
    var peerId:PeerId? {
        return renderedPeer?.peerId
    }
    
    let photo: AvatarNodeState
    
    var isGroup: Bool {
        return groupId != .root
    }
    
    
    override var stableId: AnyHashable {
        return entryId
    }
    
    var entryId: UIChatListEntryId {
        if groupId != .root {
            return .groupId(groupId)
        } else if let index = chatListIndex {
            return .chatId(index.messageIndex.id.peerId, nil)
        } else {
            preconditionFailure()
        }
    }
    
    var chatLocation: ChatLocation? {
        if let index = chatListIndex {
            return ChatLocation.peer(index.messageIndex.id.peerId)
        }
        return nil
    }

    let mentionsCount: Int32?
    let reactionsCount: Int32?

    private var date:NSAttributedString?

    private var displayLayout:(TextNodeLayout, TextNode)?
    private var chatNameLayout:(TextNodeLayout, TextNode)?

    private var messageLayout:(TextNodeLayout, TextNode)?
    private var displaySelectedLayout:(TextNodeLayout, TextNode)?
    private var messageSelectedLayout:(TextNodeLayout, TextNode)?
    private var dateLayout:(TextNodeLayout, TextNode)?
    private var dateSelectedLayout:(TextNodeLayout, TextNode)?
    private var chatNameSelectedLayout:(TextNodeLayout, TextNode)?

    private var displayNode:TextNode = TextNode()
    private var messageNode:TextNode = TextNode()
    private var displaySelectedNode:TextNode = TextNode()
    private var messageSelectedNode:TextNode = TextNode()
    private var chatNameSelectedNode:TextNode = TextNode()
    private var chatNameNode:TextNode = TextNode()

    private var messageText:NSAttributedString?
    private let titleText:NSAttributedString?
    private var chatTitleAttributed: NSAttributedString?
    
    private(set) var peerNotificationSettings:PeerNotificationSettings?
    private(set) var readState:CombinedPeerReadState?
    
    
    
//    private var badge: Badge? = nil
//    private var badgeSelected: Badge? = nil

    
    private var badgeNode:BadgeNode? = nil
    private var badgeSelectedNode:BadgeNode? = nil
    
    private var additionalBadgeNode:BadgeNode? = nil
    private var additionalBadgeSelectedNode:BadgeNode? = nil

    
    private var typingLayout:(TextNodeLayout, TextNode)?
    private var typingSelectedLayout:(TextNodeLayout, TextNode)?
    
    private let clearHistoryDisposable = MetaDisposable()
    private let deleteChatDisposable = MetaDisposable()

    private let _animateArchive:Atomic<Bool> = Atomic(value: false)
    
    var animateArchive:Bool {
        return _animateArchive.swap(false)
    }
    
    let filter: ChatListFilter?
    
    var isCollapsed: Bool {
        if let archiveStatus = archiveStatus {
            switch archiveStatus {
            case .collapsed:
                return context.layout != .minimisize
            default:
                return false
            }
        }
        return false
    }
    
    var hasRevealState: Bool {
        return canArchive || (groupId != .root && !isCollapsed)
    }
    
    var canArchive: Bool {
        if groupId != .root {
            return false
        }
        if context.peerId == peerId {
            return false
        }
        if case .ad = pinnedType {
            return false
        }
        let supportId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(777000))
        if self.peer?.id == supportId {
            return false
        }
        
        return true
    }
    
    let associatedGroupId: PeerGroupId
    
    let isMuted:Bool
    
    var hasUnread: Bool {
        return ctxBadgeNode != nil
    }
    
    let isVerified: Bool
    let isPremium: Bool
    let isScam: Bool
    let isFake: Bool

    
    private(set) var photos: [TelegramPeerPhoto] = []
    private let peerPhotosDisposable = MetaDisposable()

    
    var isOutMessage:Bool {
        if let message = message {
            return !message.flags.contains(.Incoming) && message.id.peerId != context.peerId
        }
        return false
    }
    var isRead:Bool {
        if let peer = peer as? TelegramUser {
            if let _ = peer.botInfo {
                return !peer.flags.contains(.isSupport)
            }
            if peer.id == context.peerId {
                return true
            }
        }
        if let peer = peer as? TelegramChannel {
            if case .broadcast = peer.info {
                return true
            }
        }
        
        if let readState = readState {
            if let message = message {
                return readState.isOutgoingMessageIndexRead(MessageIndex(message))
            }
        }
        
        return false
    }
    
    
    var isUnreadMarked: Bool {
        if let readState = readState {
            return readState.markedUnread
        }
        return false
    }
    
    var isSecret:Bool {
        if let renderedPeer = renderedPeer {
            return renderedPeer.peers[renderedPeer.peerId] is TelegramSecretChat
        } else {
            return false
        }
    }
    
    var isSending:Bool {
        if let message = message {
            return message.flags.contains(.Unsent)
        }
        return false
    }
    
    var isFailed: Bool {
        return self.hasFailed
    }
    
    var isSavedMessage: Bool {
        return peer?.id == context.peerId
    }
    var isRepliesChat: Bool {
        return peer?.id == repliesPeerId
    }
    
    
    
    let hasDraft:Bool
    private let hasFailed: Bool
    let pinnedType:ChatListPinnedType
    let activities: [ChatListInputActivity]
    
    var toolTip: String? {
        return messageText?.string
    }
    
    private(set) var isOnline: Bool?
    
    private(set) var hasActiveGroupCall: Bool = false
    
    private var presenceManager:PeerPresenceStatusManager?
    
    let archiveStatus: HiddenArchiveStatus?
    
    private var groupLatestPeers:[ChatListGroupReferencePeer] = []
    
    private var textLeftCutout: CGFloat = 0.0
    let contentImageSize = CGSize(width: 16, height: 16)
    let contentImageSpacing: CGFloat = 2.0
    let contentImageTrailingSpace: CGFloat = 5.0
    private(set) var contentImageSpecs: [(message: Message, media: Media, size: CGSize)] = []


    
    init(_ initialSize:NSSize, context: AccountContext, pinnedType: ChatListPinnedType, groupId: PeerGroupId, peers: [ChatListGroupReferencePeer], messages: [Message], unreadState: PeerGroupUnreadCountersCombinedSummary, unreadCountDisplayCategory: TotalUnreadCountDisplayCategory, activities: [ChatListInputActivity] = [], animateGroup: Bool = false, archiveStatus: HiddenArchiveStatus = .normal, hasFailed: Bool = false, filter: ChatListFilter? = nil) {
        self.groupId = groupId
        self.peer = nil
        self.messages = messages
        self.chatListIndex = nil
        self.activities = activities
        self.context = context
        self.mentionsCount = nil
        self.reactionsCount = nil
        self.pinnedType = pinnedType
        self.renderedPeer = nil
        self.associatedGroupId = .root
        self.isMuted = false
        self.isOnline = nil
        self.archiveStatus = archiveStatus
        self.groupLatestPeers = peers
        self.isVerified = false
        self.isPremium = false
        self.isScam = false
        self.isFake = false
        self.filter = filter
        self.hasFailed = hasFailed
        let titleText:NSMutableAttributedString = NSMutableAttributedString()
        let _ = titleText.append(string: strings().chatListArchivedChats, color: theme.chatList.textColor, font: .medium(.title))
        titleText.setSelected(color: theme.colors.underSelectedColor ,range: titleText.range)
        
        
        var message: Message?
        
        let filtered = messages.filter { !$0.text.isEmpty }
        if filtered.count == 1 {
            message = filtered[0]
        }
        if message == nil {
            message = messages.first
        }
        
        self.titleText = titleText
        if peers.count == 1 {
            self.messageText = chatListText(account: context.account, for: message, messagesCount: messages.count, folder: true)
        } else {
            let textString = NSMutableAttributedString(string: "")
            var isFirst = true
            for peer in peers {
                if let chatMainPeer = peer.peer.chatMainPeer {
                    let peerTitle = chatMainPeer.compactDisplayTitle
                    if !peerTitle.isEmpty {
                        if isFirst {
                            isFirst = false
                        } else {
                            textString.append(.initialize(string: ", ", color: theme.chatList.textColor, font: .normal(.text)))
                        }
                        textString.append(.initialize(string: peerTitle, color: peer.isUnread ? theme.chatList.textColor : theme.chatList.grayTextColor, font: .normal(.text)))
                    }
                }
            }
            self.messageText = textString
        }
        hasDraft = false
        
    

        
        if let message = message {
            let date:NSMutableAttributedString = NSMutableAttributedString()
            var time:TimeInterval = TimeInterval(message.timestamp)
            time -= context.timeDifference
            let range = date.append(string: DateUtils.string(forMessageListDate: Int32(time)), color: theme.colors.grayText, font: .normal(.short))
            date.setSelected(color: theme.colors.underSelectedColor,range: range)
            self.date = date.copy() as? NSAttributedString
            
            dateLayout = TextNode.layoutText(maybeNode: nil,  date, nil, 1, .end, NSMakeSize( .greatestFiniteMagnitude, 20), nil, false, .left)
            dateSelectedLayout = TextNode.layoutText(maybeNode: nil,  date, nil, 1, .end, NSMakeSize( .greatestFiniteMagnitude, 20), nil, true, .left)
        }
        
        
        let mutedCount = unreadState.count(countingCategory: unreadCountDisplayCategory == .chats ? .chats : .messages, mutedCategory: .all)
        
        self.highlightText = nil
        self.embeddedState = nil
        
        photo = .ArchivedChats
        
        super.init(initialSize)
        
        if case .hidden(true) = archiveStatus {
            hideItem(animated: false, reload: false)
        }
        
        
        _ = _animateArchive.swap(animateGroup)
        
        if mutedCount > 0  {
            
//            var dynamicValue = DynamicCounterTextView.make(for: "\(mutedCount)", count: "\(mutedCount)", font: .medium(.small), textColor: theme.chatList.badgeTextColor, width: 100)
//            badge = Badge(dynamicValue: dynamicValue, backgroundColor: theme.chatList.badgeMutedBackgroundColor, size: dynamicValue.size)
//
//            dynamicValue = DynamicCounterTextView.make(for: "\(mutedCount)", count: "\(mutedCount)", font: .medium(.small), textColor: theme.chatList.badgeSelectedTextColor, width: 100)
//            badgeSelected = Badge(dynamicValue: dynamicValue, backgroundColor: theme.chatList.badgeSelectedBackgroundColor, size: dynamicValue.size)

            
            badgeNode = BadgeNode(.initialize(string: "\(mutedCount)", color: theme.chatList.badgeTextColor, font: .medium(.small)), theme.chatList.badgeMutedBackgroundColor)
            badgeSelectedNode = BadgeNode(.initialize(string: "\(mutedCount)", color: theme.chatList.badgeSelectedTextColor, font: .medium(.small)), theme.chatList.badgeSelectedBackgroundColor)
        }
        
        
        //theme.chatList.badgeBackgroundColor
        
        

        _ = makeSize(initialSize.width, oldWidth: 0)
    }
    
    private let highlightText: String?
    
    private let embeddedState:StoredPeerChatInterfaceState?
    
    init(_ initialSize:NSSize,  context: AccountContext,  messages: [Message], index: ChatListIndex? = nil,  readState:CombinedPeerReadState? = nil,  isMuted:Bool = false, embeddedState:StoredPeerChatInterfaceState? = nil, pinnedType:ChatListPinnedType = .none, renderedPeer:RenderedPeer, peerPresence: PeerPresence? = nil, summaryInfo: [ChatListEntryMessageTagSummaryKey: ChatListMessageTagSummaryInfo] = [:], activities: [ChatListInputActivity] = [], highlightText: String? = nil, associatedGroupId: PeerGroupId = .root, hasFailed: Bool = false, showBadge: Bool = true, filter: ChatListFilter? = nil) {
        
        
        var embeddedState = embeddedState
        
        if let peer = renderedPeer.chatMainPeer as? TelegramChannel {
            if !peer.hasPermission(.sendMessages) {
                embeddedState = nil
            }
        }
        let interfaceState = embeddedState.flatMap(_internal_decodeStoredChatInterfaceState).flatMap({
            ChatInterfaceState.parse($0, peerId: nil, context: nil)
        })
        if let interfaceState = interfaceState {
            if interfaceState.inputState.inputText.isEmpty {
                embeddedState = nil
            }
        }
        let supportId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(777000))

        if let peerPresence = peerPresence, context.peerId != renderedPeer.peerId, renderedPeer.peerId != supportId {
            if let peerPresence = peerPresence as? TelegramUserPresence {
                let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970
                let relative = relativeUserPresenceStatus(peerPresence, timeDifference: context.timeDifference, relativeTo: Int32(timestamp))
                switch relative {
                case .online:
                    self.isOnline = true
                default:
                    self.isOnline = false
                }
            } else {
                self.isOnline = nil
            }
        } else {
            self.isOnline = nil
        }
        
        if let peer = renderedPeer.chatMainPeer as? TelegramChannel, peer.flags.contains(.hasActiveVoiceChat) {
            self.hasActiveGroupCall = true
        }
        
      
        var message: Message?
        
        let filtered = messages.filter { !$0.text.isEmpty }
        if filtered.count == 1 {
            message = filtered[0]
        }
        if message == nil {
            message = messages.first
        }
        
        self.chatListIndex = index
        self.renderedPeer = renderedPeer
        self.context = context
        self.messages = messages
        self.activities = activities
        self.pinnedType = pinnedType
        self.archiveStatus = nil
        self.hasDraft = embeddedState != nil
        self.embeddedState = embeddedState
        self.peer = renderedPeer.chatMainPeer
        self.groupId = .root
        self.hasFailed = hasFailed
        self.filter = filter
        self.associatedGroupId = associatedGroupId
        self.highlightText = highlightText
        if let peer = peer {
            self.isVerified = peer.isVerified
            self.isPremium = peer.isPremium
            self.isScam = peer.isScam
            self.isFake = peer.isFake
        } else {
            self.isVerified = false
            self.isScam = false
            self.isFake = false
            self.isPremium = false
        }
        
       
        self.isMuted = isMuted
        self.readState = readState
        
        
        let titleText:NSMutableAttributedString = NSMutableAttributedString()
        let _ = titleText.append(string: peer?.id == context.peerId ? strings().peerSavedMessages : peer?.displayTitle, color: renderedPeer.peers[renderedPeer.peerId] is TelegramSecretChat ? theme.chatList.secretChatTextColor : theme.chatList.textColor, font: .medium(.title))
        titleText.setSelected(color: theme.colors.underSelectedColor ,range: titleText.range)

        self.titleText = titleText
    
        
        if case let .ad(item) = pinnedType, let promo = item as? PromoChatListItem {
            let sponsored:NSMutableAttributedString = NSMutableAttributedString()
            let range: NSRange
            switch promo.kind {
            case let .psa(type, _):
                range = sponsored.append(string: localizedPsa("psa.chatlist", type: type), color: theme.colors.grayText, font: .normal(.short))
            case .proxy:
                range = sponsored.append(string: strings().chatListSponsoredChannel, color: theme.colors.grayText, font: .normal(.short))
            }
            sponsored.setSelected(color: theme.colors.underSelectedColor, range: range)
            self.date = sponsored
            dateLayout = TextNode.layoutText(maybeNode: nil,  sponsored, nil, 1, .end, NSMakeSize( .greatestFiniteMagnitude, 20), nil, false, .left)
            dateSelectedLayout = TextNode.layoutText(maybeNode: nil,  sponsored, nil, 1, .end, NSMakeSize( .greatestFiniteMagnitude, 20), nil, true, .left)
        } else if let message = message {
            let date:NSMutableAttributedString = NSMutableAttributedString()
            var time:TimeInterval = TimeInterval(message.timestamp)
            time -= context.timeDifference
            let range = date.append(string: DateUtils.string(forMessageListDate: Int32(time)), color: theme.colors.grayText, font: .normal(.short))
            date.setSelected(color: theme.colors.underSelectedColor, range: range)
            self.date = date.copy() as? NSAttributedString
            
            dateLayout = TextNode.layoutText(maybeNode: nil,  date, nil, 1, .end, NSMakeSize( .greatestFiniteMagnitude, 20), nil, false, .left)
            dateSelectedLayout = TextNode.layoutText(maybeNode: nil,  date, nil, 1, .end, NSMakeSize( .greatestFiniteMagnitude, 20), nil, true, .left)
            
            
            var author: Peer?
            if message.isImported, let info = message.forwardInfo {
                if let peer = info.author {
                    author = peer
                } else if let signature = info.authorSignature {
                                        
                    author = TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(0)), accessHash: nil, firstName: signature, lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [])
                }
            } else {
                author = message.author
            }
            
            if let author = author as? TelegramUser, let peer = peer, peer as? TelegramUser == nil, !peer.isChannel, embeddedState == nil {
                if !(message.media.first is TelegramMediaAction) {
                    let peerText: String = (author.id == context.account.peerId ? "\(strings().chatListYou)" : author.displayTitle)
                    
                    let attr = NSMutableAttributedString()
                    _ = attr.append(string: peerText, color: theme.chatList.peerTextColor, font: .normal(.text))
                    attr.setSelected(color: theme.colors.underSelectedColor, range: attr.range)
                    
                    self.chatTitleAttributed = attr
                }
            }
            
            let contentImageFillSize = CGSize(width: 8.0, height: contentImageSize.height)
            _ = contentImageFillSize
            let isSecret: Bool
            isSecret = renderedPeer.peers[renderedPeer.peerId] is TelegramSecretChat
            
            if embeddedState == nil, !isSecret {
                for message in messages {
                    inner: for media in message.media {
                        if !message.containsSecretMedia {
                            if let image = media as? TelegramMediaImage {
                                if let _ = largestImageRepresentation(image.representations) {
                                    let fitSize = contentImageSize
                                    contentImageSpecs.append((message, image, fitSize))
                                }
                                break inner
                            } else if let file = media as? TelegramMediaFile {
                                if file.isVideo, !file.isInstantVideo, let _ = file.dimensions, !file.probablySticker {
                                    let fitSize = contentImageSize
                                    contentImageSpecs.append((message, file, fitSize))
                                }
                                break inner
                            }
                        }
                    }
                }
            }
        }
        
        contentImageSpecs = Array(contentImageSpecs.prefix(3))
        
        for i in 0 ..< contentImageSpecs.count {
            if i != 0 {
                textLeftCutout += contentImageSpacing
            }
            textLeftCutout += contentImageSpecs[i].size.width
            if i == contentImageSpecs.count - 1 {
                textLeftCutout += contentImageTrailingSpace
            }
        }
        
        let mentions = summaryInfo[ChatListEntryMessageTagSummaryKey(
            tag: .unseenPersonalMessage,
            actionType: .consumeUnseenPersonalMessage
        )]
        
        let reactions = summaryInfo[ChatListEntryMessageTagSummaryKey(
            tag: .unseenReaction,
            actionType: .readReaction
        )]
        
        if let mentions = mentions {
            let tagSummaryCount = mentions.tagSummaryCount ?? 0
            let actionsSummaryCount = mentions.actionsSummaryCount ?? 0
            let totalMentionCount = tagSummaryCount - actionsSummaryCount
            if totalMentionCount > 0 {
                self.mentionsCount = totalMentionCount
            } else {
                self.mentionsCount = nil
            }
        } else {
            self.mentionsCount = nil
        }
       
        if let reactions = reactions {
            let tagSummaryCount = reactions.tagSummaryCount ?? 0
            let actionsSummaryCount = reactions.actionsSummaryCount ?? 0
            let totalReactionsCount = tagSummaryCount - actionsSummaryCount
            if totalReactionsCount > 0 {
                self.reactionsCount = totalReactionsCount
            } else {
                self.reactionsCount = nil
            }
        } else {
            self.reactionsCount = nil
        }
        
        if let peer = peer, peer.id != context.peerId && peer.id != repliesPeerId {
            self.photo = .PeerAvatar(peer, peer.displayLetters, peer.smallProfileImage, nil, nil)
        } else {
            self.photo = .Empty
        }
        
        super.init(initialSize)
        
        if showBadge {
            if let unreadCount = readState?.count, unreadCount > 0, mentionsCount == nil || (unreadCount > 1 || mentionsCount! != unreadCount)  {

                badgeNode = BadgeNode(.initialize(string: "\(unreadCount)", color: theme.chatList.badgeTextColor, font: .medium(.small)), isMuted ? theme.chatList.badgeMutedBackgroundColor : theme.chatList.badgeBackgroundColor)
                badgeSelectedNode = BadgeNode(.initialize(string: "\(unreadCount)", color: theme.chatList.badgeSelectedTextColor, font: .medium(.small)), theme.chatList.badgeSelectedBackgroundColor)
            } else if isUnreadMarked && mentionsCount == nil {
                badgeNode = BadgeNode(.initialize(string: " ", color: theme.chatList.badgeTextColor, font: .medium(.small)), isMuted ? theme.chatList.badgeMutedBackgroundColor : theme.chatList.badgeBackgroundColor)
                badgeSelectedNode = BadgeNode(.initialize(string: " ", color: theme.chatList.badgeSelectedTextColor, font: .medium(.small)), theme.chatList.badgeSelectedBackgroundColor)
            }
        }
       
        
      
        if let _ = self.isOnline, let presence = peerPresence as? TelegramUserPresence {
            presenceManager = PeerPresenceStatusManager(update: { [weak self] in
                self?.isOnline = false
                self?.redraw(animated: true)
            })
            
            presenceManager?.reset(presence: presence, timeDifference: Int32(context.timeDifference))
        }
        
        _ = makeSize(initialSize.width, oldWidth: 0)
        
        
        if let peer = peer, peer.isPremium {
            self.photos = syncPeerPhotos(peerId: peer.id)
            let signal = peerPhotos(context: context, peerId: peer.id, force: true) |> deliverOnMainQueue
            peerPhotosDisposable.set(signal.start(next: { [weak self] photos in
                if self?.photos != photos {
                    self?.photos = photos
                    self?.redraw(animated: true, options: .effectFade)
                }
            }))
        }
    }
    
    let margin:CGFloat = 9
    
    
    var isPinned: Bool {
        switch pinnedType {
        case .some:
            return true
        case .last:
            return true
        default:
            return false
        }
    }
    
    var isLastPinned: Bool {
        switch pinnedType {
        case .last:
            return true
        default:
            return false
        }
    }
    
    
    var isFixedItem: Bool {
        switch pinnedType {
        case .some, .ad, .last:
            return true
        default:
            return false
        }
    }
    
//    var contentDimensions: NSSize? {
//        var dimensions: CGSize?
//        if let contentImageMedia = contentImageMedia as? TelegramMediaImage {
//            dimensions = largestRepresentationForPhoto(contentImageMedia)?.dimensions.size
//        } else if let contentImageMedia = contentImageMedia as? TelegramMediaFile {
//            dimensions = contentImageMedia.dimensions?.size
//        }
//        return dimensions
//    }
    
    var isAd: Bool {
        switch pinnedType {
        case .ad:
            return true
        default:
            return false
        }
    }
    
    var badIcon: CGImage {
        return isScam ? theme.icons.scam : theme.icons.fake
    }
    var badHighlightIcon: CGImage {
        return isScam ? theme.icons.scamActive : theme.icons.fakeActive
    }
    var titleWidth:CGFloat {
        var dateSize:CGFloat = 0
        if let dateLayout = dateLayout {
            dateSize = dateLayout.0.size.width
        }
        var offset: CGFloat = 0
        if isScam || isFake {
            offset += badIcon.backingSize.width + 4
        }
        if isMuted {
            offset += theme.icons.dialogMuteImage.backingSize.width + 4
        }
        if isVerified {
            offset += 20
        }
        if isSecret {
            offset += 10
        }
        return max(300, size.width) - 50 - margin * 4 - dateSize - (isOutMessage ? isRead ? 14 : 8 : 0) - offset
    }
    var messageWidth:CGFloat {
        if let badgeNode = badgeNode {
            return (max(300, size.width) - 50 - margin * 3) - (badgeNode.size.width + 5) - (mentionsCount != nil ? 30 : 0) - (reactionsCount != nil ? 30 : 0) - (additionalBadgeNode != nil ? additionalBadgeNode!.size.width + 15 : 0) - (chatTitleAttributed != nil ? textLeftCutout : 0)
        }
        
        return (max(300, size.width) - 50 - margin * 4) - (isPinned ? 20 : 0) - (mentionsCount != nil ? 24 : 0) - (reactionsCount != nil ? 24 : 0) - (additionalBadgeNode != nil ? additionalBadgeNode!.size.width + 15 : 0) - (chatTitleAttributed != nil ? textLeftCutout : 0)
    }
    
    let leftInset:CGFloat = 50 + (10 * 2.0);
    
    override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        
        if self.groupId == .root {
            var text: NSAttributedString?
            if case let .ad(promo) = pinnedType, message == nil {
                if let promo = promo as? PromoChatListItem {
                    switch promo.kind {
                    case let .psa(_, message):
                        if let message = message {
                            let attr = NSMutableAttributedString()
                            _ = attr.append(string: message, color: theme.colors.grayText, font: .normal(.text))
                            attr.setSelected(color: theme.colors.underSelectedColor, range: attr.range)
                            text = attr
                        }
                    default:
                        break
                    }
                }
            }
            if text == nil {
                var messageText = chatListText(account: context.account, for: message, messagesCount: self.messages.count, renderedPeer: renderedPeer, embeddedState: embeddedState)
                if let query = highlightText, let copy = messageText.mutableCopy() as? NSMutableAttributedString, let range = rangeOfSearch(query, in: copy.string) {
                    if copy.range.contains(range.min) && copy.range.contains(range.max - 1), copy.range != range {
                        copy.addAttribute(.foregroundColor, value: theme.colors.text, range: range)
                        copy.addAttribute(.font, value: NSFont.medium(.text), range: range)
                        messageText = copy
                    }
                }
                text = messageText
            }
            self.messageText = text!
        }
        
       
        
        if displayLayout == nil || !displayLayout!.0.isPerfectSized || self.oldWidth > width {
            displayLayout = TextNode.layoutText(maybeNode: displayNode,  titleText, nil, 1, .end, NSMakeSize(titleWidth, size.height), nil, false, .left)
        }
        
        if displaySelectedLayout == nil || !displaySelectedLayout!.0.isPerfectSized || self.oldWidth > width {
            displaySelectedLayout = TextNode.layoutText(maybeNode: displaySelectedNode,  titleText, nil, 1, .end, NSMakeSize(titleWidth, size.height), nil, true, .left)
        }
        
        if chatNameLayout == nil || !chatNameLayout!.0.isPerfectSized || self.oldWidth > width, let chatTitleAttributed = chatTitleAttributed {
            chatNameLayout = TextNode.layoutText(maybeNode: chatNameNode, chatTitleAttributed, nil, 1, .end, NSMakeSize(titleWidth, size.height), nil, false, .left)
        }
        
        if chatNameSelectedLayout == nil || !chatNameSelectedLayout!.0.isPerfectSized || self.oldWidth > width, let chatTitleAttributed = chatTitleAttributed {
            chatNameSelectedLayout = TextNode.layoutText(maybeNode: chatNameSelectedNode, chatTitleAttributed, nil, 1, .end, NSMakeSize(titleWidth, size.height), nil, true, .left)
        }
        
        var textCutout: TextNodeCutout?
        if !textLeftCutout.isZero {
            textCutout = TextNodeCutout(position: .TopLeft, size: CGSize(width: textLeftCutout, height: 14))
        }

        
        if messageLayout == nil || !messageLayout!.0.isPerfectSized || self.oldWidth > width {
            messageLayout = TextNode.layoutText(maybeNode: messageNode,  messageText, nil, chatTitleAttributed != nil ? 1 : 2, .end, NSMakeSize(messageWidth, size.height), textCutout, false, .left, 1)
        }
        if messageSelectedLayout == nil || !messageSelectedLayout!.0.isPerfectSized || self.oldWidth > width {
            messageSelectedLayout = TextNode.layoutText(maybeNode: messageSelectedNode,  messageText, nil, chatTitleAttributed != nil ? 1 : 2, .end, NSMakeSize(messageWidth, size.height), textCutout, true, .left, 1)
        }
        return result
    }
    
    
    var markAsUnread: Bool {
        return !isSecret && !isUnreadMarked && badgeNode == nil && mentionsCount == nil
    }
    
    func collapseOrExpandArchive() {
        ChatListRowItem.collapseOrExpandArchive(context: context)
    }
    
    static func collapseOrExpandArchive(context: AccountContext) {
        context.bindings.mainController().chatList.collapseOrExpandArchive()
    }
    
    static func toggleHideArchive(context: AccountContext) {
        context.bindings.mainController().chatList.toggleHideArchive()
    }
    
    func toggleHideArchive() {
        ChatListRowItem.toggleHideArchive(context: context)
    }

    func toggleUnread() {
        if let peerId = peerId {
            _ = togglePeerUnreadMarkInteractively(postbox: context.account.postbox, viewTracker: context.account.viewTracker, peerId: peerId).start()
        }
    }
    
    func toggleMuted() {
        if let peerId = peerId {
            ChatListRowItem.toggleMuted(context: context, peerId: peerId, isMuted: isMuted)
        }
    }
    
    static func toggleMuted(context: AccountContext, peerId: PeerId, isMuted: Bool) {
        if isMuted {
            _ = context.engine.peers.togglePeerMuted(peerId: peerId).start()
        } else {
            var options:[ModalOptionSet] = []
            
            options.append(ModalOptionSet(title: strings().chatListMute1Hour, selected: false, editable: true))
            options.append(ModalOptionSet(title: strings().chatListMute4Hours, selected: false, editable: true))
            options.append(ModalOptionSet(title: strings().chatListMute8Hours, selected: false, editable: true))
            options.append(ModalOptionSet(title: strings().chatListMute1Day, selected: false, editable: true))
            options.append(ModalOptionSet(title: strings().chatListMute3Days, selected: false, editable: true))
            options.append(ModalOptionSet(title: strings().chatListMuteForever, selected: true, editable: true))
            
            let intervals:[Int32] = [60 * 60, 60 * 60 * 4, 60 * 60 * 8, 60 * 60 * 24, 60 * 60 * 24 * 3, Int32.max]
            
            showModal(with: ModalOptionSetController(context: context, options: options, selectOne: true, actionText: (strings().chatInputMute, theme.colors.accent), title: strings().peerInfoNotifications, result: { result in
                
                for (i, option) in result.enumerated() {
                    inner: switch option {
                    case .selected:
                        _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, muteInterval: intervals[i]).start()
                        break
                    default:
                        break inner
                    }
                }
                
            }), for: context.window)
        }
    }
    
    func togglePinned() {
        ChatListRowItem.togglePinned(context: context, chatLocation: chatLocation, filter: filter, associatedGroupId: associatedGroupId)
    }
    
    static func togglePinned(context: AccountContext, chatLocation: ChatLocation?, filter: ChatListFilter?, associatedGroupId: PeerGroupId) {
        if let chatLocation = chatLocation {
            let location: TogglePeerChatPinnedLocation
            
            if let filter = filter {
                location = .filter(filter.id)
            } else {
                location = .group(associatedGroupId)
            }
            let context = context
            
            _ = (context.engine.peers.toggleItemPinned(location: location, itemId: chatLocation.pinnedItemId) |> deliverOnMainQueue).start(next: { result in
                switch result {
                case .limitExceeded:
                    if let _ = filter {
                        showPremiumLimit(context: context, type: .pinInFolders)
                    } else {
                        if case .group = associatedGroupId {
                            showPremiumLimit(context: context, type: .pinInArchive)
                        } else {
                            showPremiumLimit(context: context, type: .pin)
                        }
                    }
                default:
                    break
                }
            })
        }
        
    }
    
    func toggleArchive() {
        ChatListRowItem.toggleArchive(context: context, associatedGroupId: associatedGroupId, peerId: peerId)
    }
    
    static func toggleArchive(context: AccountContext, associatedGroupId: PeerGroupId?, peerId: PeerId?) {
        if let peerId = peerId {
            switch associatedGroupId {
            case .root:
                let postbox = context.account.postbox
                context.bindings.mainController().chatList.setAnimateGroupNextTransition(Namespaces.PeerGroup.archive)
                _ = updatePeerGroupIdInteractively(postbox: postbox, peerId: peerId, groupId: Namespaces.PeerGroup.archive).start()
            default:
                 _ = updatePeerGroupIdInteractively(postbox: context.account.postbox, peerId: peerId, groupId: .root).start()
            }
        }
    }
    
    func delete() {
        if let peerId = peerId {
            let signal = removeChatInteractively(context: context, peerId: peerId, userId: peer?.id)
            _ = signal.start()
        }
    }
    
    override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {

        let context = self.context
        let peerId = self.peerId
        let peer = self.peer
        let filter = self.filter
        let isMuted = self.isMuted
        let chatLocation = self.chatLocation
        let associatedGroupId = self.associatedGroupId
        let isAd = self.isAd
        let renderedPeer = self.renderedPeer
        let canArchive = self.canArchive
        let groupId = self.groupId
        let markAsUnread = self.markAsUnread
        let isPinned = self.isPinned
        let archiveStatus = archiveStatus
        let isSecret = self.isSecret
        let peerNotificationSettings = self.peerNotificationSettings as? TelegramPeerNotificationSettings
        let isUnread = badgeNode != nil || mentionsCount != nil || isUnreadMarked
        let deleteChat:()->Void = { [weak self] in
            self?.delete()
        }
        
        let togglePin:()->Void = {
           ChatListRowItem.togglePinned(context: context, chatLocation: chatLocation, filter: filter, associatedGroupId: associatedGroupId)
        }
        
        let toggleArchive:()->Void = {
            if let peerId = peerId {
                ChatListRowItem.toggleArchive(context: context, associatedGroupId: associatedGroupId, peerId: peerId)
            }
        }
        
        let toggleMute:()->Void = {
            if let peerId = peerId {
                ChatListRowItem.toggleMuted(context: context, peerId: peerId, isMuted: isMuted)
            }
        }
        
        let cachedData:Signal<CachedPeerData?, NoError>
        if let peerId = peerId {
            cachedData = context.account.viewTracker.peerView(peerId) |> map {
                $0.cachedData
            }
        } else {
            cachedData = .single(nil)
        }
        
        let soundsDataSignal = combineLatest(queue: .mainQueue(), appNotificationSettings(accountManager: context.sharedContext.accountManager), context.engine.peers.notificationSoundList(), context.account.postbox.transaction { transaction -> TelegramPeerNotificationSettings? in
            if let peerId = peerId {
                return transaction.getPeerNotificationSettings(peerId) as? TelegramPeerNotificationSettings
            } else {
                return nil
            }
        })

        
        
        return combineLatest(queue: .mainQueue(), chatListFilterPreferences(engine: context.engine), cachedData, soundsDataSignal) |> take(1) |> map { filters, cachedData, soundsData -> [ContextMenuItem] in
            
            var items:[ContextMenuItem] = []
            
            let canDeleteForAll: Bool?
            if let cachedData = cachedData as? CachedChannelData {
                canDeleteForAll = cachedData.flags.contains(.canDeleteHistory)
            } else {
                canDeleteForAll = nil
            }
            
            var firstGroup:[ContextMenuItem] = []
            var secondGroup:[ContextMenuItem] = []
            var thirdGroup:[ContextMenuItem] = []

            if let mainPeer = peer, let peerId = peerId, let peer = renderedPeer?.peers[peerId] {
                                    
                if !isAd && groupId == .root {
                    firstGroup.append(ContextMenuItem(!isPinned ? strings().chatListContextPin : strings().chatListContextUnpin, handler: togglePin, itemImage: !isPinned ? MenuAnimation.menu_pin.value : MenuAnimation.menu_unpin.value))
                }
                
                if groupId == .root, (canArchive || associatedGroupId != .root), filter == nil {
                    secondGroup.append(ContextMenuItem(associatedGroupId == .root ? strings().chatListSwipingArchive : strings().chatListSwipingUnarchive, handler: toggleArchive, itemImage: associatedGroupId == .root ? MenuAnimation.menu_archive.value : MenuAnimation.menu_unarchive.value))
                }
                
                if context.peerId != peer.id, !isAd {
                    let muteItem = ContextMenuItem(isMuted ? strings().chatListContextUnmute : strings().chatListContextMute, handler: toggleMute, itemImage: isMuted ? MenuAnimation.menu_unmuted.value : MenuAnimation.menu_mute.value)
                    
                    let sound: ContextMenuItem = ContextMenuItem(strings().chatListContextSound, handler: {
                        
                    }, itemImage: MenuAnimation.menu_music.value)
                    
                    let soundList = ContextMenu()
                    
                    
                    let selectedSound: PeerMessageSound
                    if let peerNotificationSettings = soundsData.2 {
                        selectedSound = peerNotificationSettings.messageSound
                    } else {
                        selectedSound = .default
                    }
                    
                    let playSound:(PeerMessageSound) -> Void = { tone in
                        let effectiveTone: PeerMessageSound
                        if tone == .default {
                            effectiveTone = soundsData.0.tone
                        } else {
                            effectiveTone = tone
                        }
                        
                        if effectiveTone != .default && effectiveTone != .none {
                            let path = fileNameForNotificationSound(postbox: context.account.postbox, sound: effectiveTone, defaultSound: nil, list: soundsData.1)
                            
                            _ = path.start(next: { resource in
                                if let resource = resource {
                                    let path = resourcePath(context.account.postbox, resource)
                                    SoundEffectPlay.play(postbox: context.account.postbox, path: path)
                                }
                            })
                        }
                    }
                    
                    let updateSound:(PeerMessageSound)->Void = { tone in
                        playSound(tone)
                        _ = context.engine.peers.updatePeerNotificationSoundInteractive(peerId: peerId, sound: tone).start()

                    }
                    
                    soundList.addItem(ContextMenuItem(localizedPeerNotificationSoundString(sound: .default, default: nil, list: nil), handler: {
                        updateSound(.default)
                    }, hover: {
                        playSound(.default)
                    }, state: selectedSound == .default ? .on : nil))
                    
                    soundList.addItem(ContextMenuItem(localizedPeerNotificationSoundString(sound: .none, default: nil, list: nil), handler: {
                        updateSound(.none)
                    }, hover: {
                        playSound(.none)
                    }, state: selectedSound == .none ? .on : nil))
                    soundList.addItem(ContextSeparatorItem())
                    
                    
                    
                    if let sounds = soundsData.1 {
                        for sound in sounds.sounds {
                            let tone: PeerMessageSound = .cloud(fileId: sound.file.fileId.id)
                            soundList.addItem(ContextMenuItem(localizedPeerNotificationSoundString(sound: .cloud(fileId: sound.file.fileId.id), default: nil, list: sounds), handler: {
                                updateSound(tone)
                            }, hover: {
                                playSound(tone)
                            }, state: selectedSound == .cloud(fileId: sound.file.fileId.id) ? .on : nil))
                        }
                        if !sounds.sounds.isEmpty {
                            soundList.addItem(ContextSeparatorItem())
                        }
                    }
                    
                 
                    for i in 0 ..< 12 {
                        let sound: PeerMessageSound = .bundledModern(id: Int32(i))
                        soundList.addItem(ContextMenuItem(localizedPeerNotificationSoundString(sound: sound, default: nil, list: soundsData.1), handler: {
                            updateSound(sound)
                        }, hover: {
                            playSound(sound)
                        }, state: selectedSound == sound ? .on : nil))
                    }
                    soundList.addItem(ContextSeparatorItem())
                    for i in 0 ..< 8 {
                        let sound: PeerMessageSound = .bundledClassic(id: Int32(i))
                        soundList.addItem(ContextMenuItem(localizedPeerNotificationSoundString(sound: sound, default: nil, list: soundsData.1), handler: {
                            updateSound(sound)
                        }, hover: {
                            playSound(sound)
                        }, state: selectedSound == sound ? .on : nil))
                    }
                    
                    
                    sound.submenu = soundList
                    
                    
                    if !isMuted {
                        let submenu = ContextMenu()
                        submenu.addItem(ContextMenuItem(strings().chatListMute1Hour, handler: {
                            _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, muteInterval: 60 * 60 * 1).start()
                        }, itemImage: MenuAnimation.menu_mute_for_1_hour.value))
                        
                        submenu.addItem(ContextMenuItem(strings().chatListMute3Days, handler: {
                            _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, muteInterval: 60 * 60 * 24 * 3).start()
                        }, itemImage: MenuAnimation.menu_mute_for_2_days.value))
                        
                        submenu.addItem(ContextMenuItem(strings().chatListMuteForever, handler: {
                            _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, muteInterval: Int32.max).start()
                        }, itemImage: MenuAnimation.menu_mute.value))
                        
                        submenu.addItem(ContextSeparatorItem())
                        submenu.addItem(sound)
                        
                        muteItem.submenu = submenu
                    }
                    /*
                     else {
                         let submenu = ContextMenu()
                         submenu.addItem(sound)
                         muteItem.submenu = submenu
                     }
                     
                     */
                    
                    firstGroup.append(muteItem)
                }
                
                if mainPeer is TelegramUser {
                    thirdGroup.append(ContextMenuItem(strings().chatListContextClearHistory, handler: {
                        clearHistory(context: context, peer: peer, mainPeer: mainPeer, canDeleteForAll: canDeleteForAll)
                    }, itemImage: MenuAnimation.menu_clear_history.value))
                    thirdGroup.append(ContextMenuItem(strings().chatListContextDeleteChat, handler: deleteChat, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                }
                
                if !isSecret {
                    if markAsUnread {
                        firstGroup.append(ContextMenuItem(strings().chatListContextMaskAsUnread, handler: {
                            _ = togglePeerUnreadMarkInteractively(postbox: context.account.postbox, viewTracker: context.account.viewTracker, peerId: peerId).start()
                            
                        }, itemImage: MenuAnimation.menu_unread.value))
                        
                    } else if isUnread {
                        firstGroup.append(ContextMenuItem(strings().chatListContextMaskAsRead, handler: {
                            _ = togglePeerUnreadMarkInteractively(postbox: context.account.postbox, viewTracker: context.account.viewTracker, peerId: peerId).start()
                        }, itemImage: MenuAnimation.menu_read.value))
                    }
                }
                
                if isAd {
                    firstGroup.append(ContextMenuItem(strings().chatListContextHidePromo, handler: {
                        context.bindings.mainController().chatList.hidePromoItem(peerId)
                    }, itemImage: MenuAnimation.menu_archive.value))
                }
                if let peer = peer as? TelegramGroup, !isAd {
                    thirdGroup.append(ContextMenuItem(strings().chatListContextClearHistory, handler: {
                        clearHistory(context: context, peer: peer, mainPeer: mainPeer, canDeleteForAll: canDeleteForAll)
                    }, itemImage: MenuAnimation.menu_delete.value))
                    thirdGroup.append(ContextMenuItem(strings().chatListContextDeleteAndExit, handler: deleteChat, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                } else if let peer = peer as? TelegramChannel, !isAd, !peer.flags.contains(.hasGeo) {
                    
                    if case .broadcast = peer.info {
                        thirdGroup.append(ContextMenuItem(strings().chatListContextLeaveChannel, handler: deleteChat, itemMode: .destruct, itemImage: MenuAnimation.menu_leave.value))
                    } else if !isAd {
                        if peer.addressName == nil {
                            thirdGroup.append(ContextMenuItem(strings().chatListContextClearHistory, handler: {
                                clearHistory(context: context, peer: peer, mainPeer: mainPeer, canDeleteForAll: canDeleteForAll)
                            }, itemImage: MenuAnimation.menu_clear_history.value))
                        } 
                        thirdGroup.append(ContextMenuItem(strings().chatListContextLeaveGroup, handler: deleteChat, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                    }
                }
                
            } else {
                if !isAd, groupId == .root {
                    firstGroup.append(ContextMenuItem(!isPinned ? strings().chatListContextPin : strings().chatListContextUnpin, handler: {
                        ChatListRowItem.togglePinned(context: context, chatLocation: chatLocation, filter: filter, associatedGroupId: associatedGroupId)
                    }, itemImage: isPinned ? MenuAnimation.menu_unpin.value : MenuAnimation.menu_pin.value))
                }
            }
            
            if groupId != .root, context.layout != .minimisize, let archiveStatus = archiveStatus {
                switch archiveStatus {
                case .collapsed:
                    firstGroup.append(ContextMenuItem(strings().chatListRevealActionExpand , handler: {
                        ChatListRowItem.collapseOrExpandArchive(context: context)
                    }, itemImage: MenuAnimation.menu_expand.value))
                default:
                    firstGroup.append(ContextMenuItem(strings().chatListRevealActionCollapse, handler: {
                        ChatListRowItem.collapseOrExpandArchive(context: context)
                    }, itemImage: MenuAnimation.menu_collapse.value))
                }
            }
            
            var submenu: [ContextMenuItem] = []
            if let peerId = peerId, peerId.namespace != Namespaces.Peer.SecretChat {
                for item in filters.list {
                    
                    let menuItem = ContextMenuItem(item.title, handler: {
                        
                        let limit = context.isPremium ? context.premiumLimits.dialog_filters_chats_limit_premium : context.premiumLimits.dialog_filters_chats_limit_default
                        
                        let isEnabled = item.data.includePeers.peers.contains(peerId) || item.data.includePeers.peers.count < limit
                        if isEnabled {
                            _ = context.engine.peers.updateChatListFiltersInteractively({ list in
                                var list = list
                                for (i, folder) in list.enumerated() {
                                    var folder = folder
                                    if folder.id == item.id {
                                        if item.data.includePeers.peers.contains(peerId) {
                                            var peers = folder.data.includePeers.peers
                                            peers.removeAll(where: { $0 == peerId })
                                            folder.data.includePeers.setPeers(peers)
                                        } else {
                                            folder.data.includePeers.setPeers(folder.data.includePeers.peers + [peerId])
                                        }
                                        list[i] = folder

                                    }
                                }
                                return list
                            }).start()
                        } else {
                            if context.isPremium {
                                alert(for: context.window, info: strings().chatListFilterIncludeLimitReached)
                            } else {
                                showPremiumLimit(context: context, type: .chatInFolders)
                            }
                        }
                       
                    }, state: item.data.includePeers.peers.contains(peerId) ? .on : nil, itemImage: FolderIcon(item).emoticon.drawable.value)
                    
                    submenu.append(menuItem)
                }
            }
            
            if !submenu.isEmpty {
                let item = ContextMenuItem(strings().chatListFilterAddToFolder, itemImage: MenuAnimation.menu_add_to_folder.value)
                let menu = ContextMenu()
                for item in submenu {
                    menu.addItem(item)
                }
                item.submenu = menu
                secondGroup.append(item)
            }
            
            if !firstGroup.isEmpty {
                items.append(contentsOf: firstGroup)
            }
            if !secondGroup.isEmpty {
                if !firstGroup.isEmpty {
                    items.append(ContextSeparatorItem())
                }
                items.append(contentsOf: secondGroup)
            }
            if !thirdGroup.isEmpty {
                if !firstGroup.isEmpty || !secondGroup.isEmpty {
                    items.append(ContextSeparatorItem())
                }
                items.append(contentsOf: thirdGroup)
            }
            
            return items
        }
    }
    
    var ctxDisplayLayout:(TextNodeLayout, TextNode)? {
        if isSelected && context.layout != .single {
            return displaySelectedLayout
        }
        return displayLayout
    }
    
    var ctxChatNameLayout:(TextNodeLayout, TextNode)? {
        if isSelected && context.layout != .single {
            return chatNameSelectedLayout
        }
        return chatNameLayout
    }
    
    var ctxMessageLayout:(TextNodeLayout, TextNode)? {
        if isSelected && context.layout != .single {
            if let typingSelectedLayout = typingSelectedLayout {
                return typingSelectedLayout
            }
            return messageSelectedLayout
        }
        if let typingLayout = typingLayout {
            return typingLayout
        }
        return messageLayout
    }
    var ctxDateLayout:(TextNodeLayout, TextNode)? {
        if isSelected && context.layout != .single {
            return dateSelectedLayout
        }
        return dateLayout
    }
    
    var ctxBadgeNode:BadgeNode? {
        if isSelected && context.layout != .single {
            return badgeSelectedNode
        }
        return badgeNode
    }
    
//    var ctxBadge: Badge? {
//        if isSelected && context.layout != .single {
//            return badgeSelected
//        }
//        return badge
//    }
    
    var ctxAdditionalBadgeNode:BadgeNode? {
        if isSelected && context.layout != .single {
            return additionalBadgeSelectedNode
        }
        return additionalBadgeNode
    }
    
    
    override var instantlyResize: Bool {
        return true
    }

    deinit {
        clearHistoryDisposable.dispose()
        deleteChatDisposable.dispose()
    }
    
    override func viewClass() -> AnyClass {
        return ChatListRowView.self
    }
  
    override var height: CGFloat {
        if let archiveStatus = archiveStatus, context.layout != .minimisize {
            switch archiveStatus {
            case .collapsed:
                return 30
            default:
                return 70
            }
        }
        return 70
    }
    
}
