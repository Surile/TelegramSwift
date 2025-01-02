//
//  PreviewStarGiftController.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 04.09.2024.
//  Copyright © 2024 Telegram. All rights reserved.
//

import Foundation
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
import InputView
import InAppPurchaseManager
import ColorPalette

private final class LimitedRowItem : GeneralRowItem {
    fileprivate let availability: StarGift.Gift.Availability
    init(_ initialSize: NSSize, stableId: AnyHashable, availability: StarGift.Gift.Availability) {
        self.availability = availability
        super.init(initialSize, height: 30 + 48, stableId: stableId)
    }
    
    override func viewClass() -> AnyClass {
        return LimitedRowView.self
    }
}

private final class LimitedRowView : GeneralRowView {
    
    
    private final class BadgeView : View {
        private let shapeLayer = SimpleShapeLayer()
        private let foregroundLayer = SimpleGradientLayer()
        private let textView = InteractiveTextView()
        private let container = View()
        
        private(set) var tailPosition: CGFloat = 0.0
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            
            textView.userInteractionEnabled = false
            
            foregroundLayer.colors = [theme.colors.accent, theme.colors.accent].map { $0.cgColor }
            foregroundLayer.startPoint = NSMakePoint(0, 0.5)
            foregroundLayer.endPoint = NSMakePoint(1, 0.2)
            foregroundLayer.mask = shapeLayer
            
            
            self.layer?.masksToBounds = false
            self.foregroundLayer.masksToBounds = false
            
            
            self.layer?.addSublayer(foregroundLayer)


            self.layer?.masksToBounds = false
            
            shapeLayer.fillColor = NSColor.red.cgColor
            shapeLayer.transform = CATransform3DMakeScale(1.0, -1.0, 1.0)
            

            
            container.addSubview(textView)
            addSubview(container)
            container.layer?.masksToBounds = false
        }
        
        func update(sliderValue: Int64, realValue: Int64, max maxValue: Int64) -> NSSize {
            
            
            let attr = NSMutableAttributedString()
            attr.append(string: "\(realValue.formattedWithSeparator)", color: theme.colors.underSelectedColor, font: .medium(16))
            let textLayout = TextViewLayout(attr)
            textLayout.measure(width: .greatestFiniteMagnitude)
            self.textView.set(text: textLayout, context: nil)

            
            container.setFrameSize(NSMakeSize(container.subviewsWidthSize.width + 2, container.subviewsWidthSize.height))
            
            self.tailPosition = max(0, min(1, CGFloat(sliderValue) / CGFloat(maxValue)))
                    
            let size = NSMakeSize(container.frame.width + 30, frame.height)
            
            
            foregroundLayer.frame = size.bounds.insetBy(dx: 0, dy: -10)
            shapeLayer.frame = foregroundLayer.frame.focus(size)
            
            shapeLayer.path = generateRoundedRectWithTailPath(rectSize: size, tailPosition: tailPosition)._cgPath
            
            return size
            
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            transition.updateFrame(view: container, frame: container.centerFrameX(y: 1))

            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: -3))
            
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
         //   shapeLayer.frame = bounds
        }
    }

    private class LineView : View {
        private var availability: StarGift.Gift.Availability?
        private let limitedView = TextView()
        private let totalView = TextView()
        
        private let limitColorMask = SimpleLayer()
        private let totalColorMask = SimpleLayer()
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            self.layer?.cornerRadius = 10
            addSubview(limitedView)
            addSubview(totalView)
            
            self.layer?.addSublayer(self.limitColorMask)
            self.layer?.addSublayer(self.totalColorMask)
            
            limitedView.userInteractionEnabled = false
            limitedView.isSelectable = false
            
            totalView.userInteractionEnabled = false
            totalView.isSelectable = false
        }
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func draw(_ layer: CALayer, in ctx: CGContext) {
            super.draw(layer, in: ctx)
            
            guard let availability else {
                return
            }
            
            let percent = CGFloat(availability.remains) / CGFloat(availability.total)
            
            ctx.setFillColor(theme.colors.grayForeground.cgColor)
            ctx.fill(bounds)
            
            
            ctx.setFillColor(theme.colors.accent.cgColor)
            ctx.fill(NSMakeRect(0, 0, bounds.width * percent, bounds.height))
            
        }
        
        func set(availability: StarGift.Gift.Availability) {
            self.availability = availability
            needsDisplay = true
            
            
            
            
            
            let limitedLayout = TextViewLayout(.initialize(string: strings().giftingStarGiftLimited, color: .white, font: .medium(.text)))
            limitedLayout.measure(width: .greatestFiniteMagnitude)
            self.limitedView.update(limitedLayout)
            
            
            let percent = CGFloat(availability.remains) / CGFloat(availability.total)

            let w = frame.width * percent

            limitColorMask.contents = generateImage(limitedLayout.layoutSize, contextGenerator: { size, ctx in
                let width = w - 10
                ctx.setFillColor(theme.colors.underSelectedColor.cgColor)
                ctx.fill(NSMakeRect(0, 0, width, size.height))
                
                ctx.setFillColor(theme.colors.grayIcon.cgColor)
                ctx.fill(NSMakeRect(width, 0, size.width - width, size.height))
            })
            
            limitColorMask.mask = self.limitedView.drawingLayer
            
                        
            let totalLayout = TextViewLayout(.initialize(string: availability.total.formattedWithSeparator, color: .white, font: .medium(.text)))
            totalLayout.measure(width: .greatestFiniteMagnitude)
            self.totalView.update(totalLayout)
            
            totalColorMask.contents = generateImage(totalLayout.layoutSize, contextGenerator: { size, ctx in
                let minx = frame.width - 10 - size.width
                
                let width = max(0,  w - minx)
                ctx.setFillColor(theme.colors.underSelectedColor.cgColor)
                ctx.fill(NSMakeRect(0, 0, width, size.height))
                
                ctx.setFillColor(theme.colors.grayIcon.cgColor)
                ctx.fill(NSMakeRect(width, 0, size.width - width, size.height))
                
            })
            
            totalColorMask.mask = self.totalView.drawingLayer

        }
        
        override func layout() {
            super.layout()
            limitedView.centerY(x: 10)
            limitColorMask.frame = limitedView.frame
            self.totalView.centerY(x: frame.width - totalView.frame.width - 10)
            self.totalColorMask.frame = totalView.frame
        }
    }
    
    private let lineView = LineView(frame: .zero)
    private let badgeView = BadgeView(frame: NSMakeSize(100, 30).bounds)
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(lineView)
        addSubview(badgeView)
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? LimitedRowItem else {
            return
        }
        
        let availability = item.availability

        lineView.frame = NSMakeRect(20, frame.height - 30, frame.width - 40, 30)

        lineView.set(availability: item.availability)
        let size = badgeView.update(sliderValue: Int64(availability.remains), realValue: Int64(availability.remains), max: Int64(availability.total))
        badgeView.setFrameSize(size)
        
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        
        guard let item = item as? LimitedRowItem else {
            return
        }
        
        let availability = item.availability
        let percent = CGFloat(availability.remains) / CGFloat(availability.total)
        
        let w = floorToScreenPixels(percent * (frame.width - 40))
        
        badgeView.setFrameOrigin(NSMakePoint(20 + w - badgeView.frame.width * badgeView.tailPosition, 10))

        lineView.frame = NSMakeRect(20, frame.height - 30, frame.width - 40, 30)
        
    }
    
}

private final class PreviewRowItem : GeneralRowItem {
    let context: AccountContext
    let peer: EnginePeer
    let source: PreviewGiftSource
    let includeUpgrade: Bool
    let headerLayout: TextViewLayout
    
    let presentation: TelegramPresentationTheme
    let titleLayout: TextViewLayout
    let infoLayout: TextViewLayout
    
    init(_ initialSize: NSSize, stableId: AnyHashable, peer: EnginePeer, myPeer: EnginePeer, source: PreviewGiftSource, message: Updated_ChatTextInputState, context: AccountContext, viewType: GeneralViewType, includeUpgrade: Bool) {
        self.context = context
        self.peer = peer
        self.source = source
        self.includeUpgrade = includeUpgrade
        self.presentation = theme.withUpdatedChatMode(true).withUpdatedWallpaper(.init(wallpaper: .builtin, associated: nil)).withUpdatedColors(dayClassicPalette)
        
        let titleAttr = NSMutableAttributedString()
        
        switch source {
        case .starGift(let option):
            titleAttr.append(string: strings().chatServiceStarGiftFrom("\(clown_space)\(myPeer._asPeer().compactDisplayTitle)"), color: presentation.chatServiceItemTextColor, font: .medium(.header))
            titleAttr.insertEmbedded(.embeddedAvatar(myPeer), for: clown)
        case .premium(let option):
            titleAttr.append(string: strings().giftPremiumHeader(timeIntervalString(Int(option.months) * 30 * 60 * 60 * 24)), color: presentation.chatServiceItemTextColor, font: .medium(.header))
        }
        
        
        self.titleLayout = TextViewLayout(titleAttr, alignment: .center)
        
        let infoText = NSMutableAttributedString()
        
        if !message.string.isEmpty {
            let textInputState = message.textInputState()
            let entities = textInputState.messageTextEntities()
            
            let attr = ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: entities)], for: message.string, message: nil, context: context, fontSize: 13, openInfo: { _, _, _, _ in }, textColor: presentation.chatServiceItemTextColor, isDark: theme.colors.isDark, bubbled: true).mutableCopy() as! NSMutableAttributedString
            InlineStickerItem.apply(to: attr, associatedMedia: textInputState.inlineMedia, entities: entities, isPremium: context.isPremium)
            infoText.append(attr)
        } else {
            switch source {
            case .starGift(let option):
                infoText.append(string: strings().starsGiftPreviewDisplay(strings().starListItemCountCountable(Int(option.native.generic!.convertStars))) , color: presentation.chatServiceItemTextColor, font: .normal(.text))
            case .premium:
                infoText.append(string: strings().giftPremiumText, color: presentation.chatServiceItemTextColor, font: .normal(.text))
            }
             
        }
        
        self.infoLayout = .init(infoText, alignment: .center)
        
        switch source {
        case .starGift(let option):
            headerLayout = .init(.initialize(string: strings().chatServicePremiumGiftSent(myPeer._asPeer().compactDisplayTitle, strings().starListItemCountCountable(Int(option.stars))), color: presentation.chatServiceItemTextColor, font: .normal(.text)), alignment: .center)
        case .premium(let option):
            headerLayout = .init(.initialize(string: strings().chatServicePremiumGiftSent(myPeer._asPeer().compactDisplayTitle, option.price), color: presentation.chatServiceItemTextColor, font: .normal(.text)), alignment: .center)
        }
        
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }
    
    var shouldBlurService: Bool {
        return true
    }
    
    var isBubbled: Bool {
        return presentation.bubbled
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        headerLayout.measure(width: blockWidth - 40)
        titleLayout.measure(width: 200 - 20)
        infoLayout.measure(width: 200 - 20)
        
//        if shouldBlurService {
//            headerLayout.generateAutoBlock(backgroundColor: presentation.chatServiceItemColor.withAlphaComponent(1))
//        } else {
//            headerLayout.generateAutoBlock(backgroundColor: presentation.chatServiceItemColor)
//        }
//
        return true
    }
    
    override func viewClass() -> AnyClass {
        return PreviewRowView.self
    }
    
    override var height: CGFloat {
        var height: CGFloat = 0
        height += 20
        height += headerLayout.layoutSize.height
        height += blockHeight
        height += 20
        return height
    }
    
    var blockHeight: CGFloat {
        var height: CGFloat = 0
        height += 100
        height += 15
        height += titleLayout.layoutSize.height
        height += 2
        height += infoLayout.layoutSize.height
        height += 10
        height += 40
        return height
    }
    
    override var hasBorder: Bool {
        return false
    }
}

private final class PreviewRowView : GeneralContainableRowView {
    private let backgroundView = BackgroundView(frame: .zero)
    private let headerView = TextView()
    private let headerVisualEffect: VisualEffect = VisualEffect(frame: .zero)

    private final class BlockView : View {
        private let sticker = MediaAnimatedStickerView(frame: NSMakeRect(0, 0, 100, 100))
        private let headerView = InteractiveTextView()
        private let textView = InteractiveTextView()
        private var visualEffect: VisualEffect?
        private var imageView: ImageView?
        
        private let button = TextButton()
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(sticker)
            addSubview(headerView)
            addSubview(textView)
            addSubview(button)
            
            textView.userInteractionEnabled = false
            
            layer?.cornerRadius = 10
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        
        func update(item: PreviewRowItem, animated: Bool) {
            headerView.set(text: item.titleLayout, context: item.context)
            textView.set(text: item.infoLayout, context: item.context)
            
            button.userInteractionEnabled = false
            button.set(font: .medium(.text), for: .Normal)
            button.set(color: item.presentation.chatServiceItemTextColor, for: .Normal)
            button.set(background: item.shouldBlurService ? item.presentation.blurServiceColor : item.presentation.chatServiceItemColor, for: .Normal)
            button.set(text: item.includeUpgrade ? strings().giftUpgradeUpgrade : strings().chatServiceGiftView, for: .Normal)
            button.sizeToFit(NSMakeSize(20, 14))
            button.layer?.cornerRadius = button.frame.height / 2
            switch item.source {
            case .starGift(let option):
                let parameters = ChatAnimatedStickerMediaLayoutParameters(playPolicy: .onceEnd, media: option.media)
                sticker.update(with: option.media, size: sticker.frame.size, context: item.context, table: nil, parameters: parameters, animated: animated)
            case .premium(let option):
                let media: TelegramMediaFile
                switch option.months {
                case 3:
                    media = LocalAnimatedSticker.premium_gift_3.file
                case 6:
                    media = LocalAnimatedSticker.premium_gift_6.file
                default:
                    media = LocalAnimatedSticker.premium_gift_12.file
                }
                let parameters = ChatAnimatedStickerMediaLayoutParameters(playPolicy: .onceEnd, media: media)
                sticker.update(with: media, size: sticker.frame.size, context: item.context, table: nil, parameters: parameters, animated: animated)
            }
            
            if item.shouldBlurService {
                let current: VisualEffect
                if let view = self.visualEffect {
                    current = view
                } else {
                    current = VisualEffect(frame: bounds)
                    self.visualEffect = current
                    addSubview(current, positioned: .below, relativeTo: self.subviews.first)
                }
                current.bgColor = item.presentation.blurServiceColor
                
                self.backgroundColor = .clear
                
            } else {
                if let view = visualEffect {
                    performSubviewRemoval(view, animated: animated)
                    self.visualEffect = nil
                }
                self.backgroundColor = item.presentation.chatServiceItemColor
            }
            
            switch item.source {
            case .starGift(let option):
                if let availability = option.native.generic?.availability {
                    let current: ImageView
                    if let view = self.imageView {
                        current = view
                    } else {
                        current = ImageView()
                        addSubview(current)
                        self.imageView = current
                    }
                    
                    let text: String = strings().starTransactionAvailabilityOf(1, Int(availability.total).prettyNumber)
                    let color = item.presentation.chatServiceItemColor
                    
                    let ribbon = generateGradientTintedImage(image: NSImage(named: "GiftRibbon")?.precomposed(), colors: [color.withMultipliedBrightnessBy(1.1), color.withMultipliedBrightnessBy(0.9)], direction: .diagonal)!
                    
                    current.image = generateGiftBadgeBackground(background: ribbon, text: text)
                    current.sizeToFit()
                } else if let view = self.imageView {
                    performSubviewRemoval(view, animated: animated)
                    self.imageView = nil
                }
            case .premium:
                if let view = self.imageView {
                    performSubviewRemoval(view, animated: animated)
                    self.imageView = nil
                }
            }
            
            
            
            needsLayout = true
        }
        
        override func layout() {
            super.layout()
            sticker.centerX(y: 0)
            visualEffect?.frame = bounds
            if let imageView {
                imageView.setFrameOrigin(frame.width - imageView.frame.width, 0)
            }

            headerView.centerX(y: sticker.frame.maxY + 10)
            textView.centerX(y: headerView.frame.maxY + 2)
            button.centerX(y: textView.frame.maxY + 10)
        }
    }
    
    private let blockView = BlockView(frame: .zero)
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(headerVisualEffect)
        addSubview(headerView)
        
        headerView.userInteractionEnabled = false
        headerView.isSelectable = false
        
        addSubview(blockView)
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? PreviewRowItem else {
            return
        }
        
        headerVisualEffect.bgColor = item.presentation.blurServiceColor
        
        headerView.update(item.headerLayout)
        blockView.update(item: item, animated: animated)
        backgroundView.backgroundMode = item.presentation.backgroundMode
    }
  
    
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        guard let item = item as? PreviewRowItem else {
            return
        }
    
        transition.updateFrame(view: backgroundView, frame: containerView.bounds)
        transition.updateFrame(view: headerView, frame: headerView.centerFrameX(y: 15))
        transition.updateFrame(view: headerVisualEffect, frame: headerView.frame.insetBy(dx: -10, dy: -5))
        transition.updateFrame(view: headerVisualEffect, frame: headerView.frame.insetBy(dx: -10, dy: -5))

        headerVisualEffect.layer?.cornerRadius = headerVisualEffect.frame.height / 2
        
        transition.updateFrame(view: blockView, frame: containerView.bounds.focusX(NSMakeSize(200, item.blockHeight), y: headerView.frame.maxY + 15))
        
    }
    
}

private final class Arguments {
    let context: AccountContext
    let toggleAnonymous: ()->Void
    let toggleUpgrade: ()->Void
    let updateState:(Updated_ChatTextInputState)->Void
    let previewUpgrade:(PeerStarGift)->Void
    init(context: AccountContext, toggleAnonymous: @escaping()->Void, updateState:@escaping(Updated_ChatTextInputState)->Void, toggleUpgrade: @escaping()->Void, previewUpgrade:@escaping(PeerStarGift)->Void) {
        self.context = context
        self.toggleAnonymous = toggleAnonymous
        self.updateState = updateState
        self.toggleUpgrade = toggleUpgrade
        self.previewUpgrade = previewUpgrade
    }
}

private struct State : Equatable {
    var peer: EnginePeer
    var myPeer: EnginePeer
    var option: PreviewGiftSource
    var isAnonymous: Bool = false
    var textState: Updated_ChatTextInputState
    var starsState: StarsContext.State?
    var includeUpgrade: Bool = false
}

private let _id_preview = InputDataIdentifier("_id_preview")
private let _id_input = InputDataIdentifier("_id_input")
private let _id_anonymous = InputDataIdentifier("_id_anonymous")
private let _id_limit = InputDataIdentifier("_id_limit")
private let _id_upgrade = InputDataIdentifier("_id_upgrade")


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    switch state.option {
    case .starGift(let option):
        if let limited = option.native.generic?.availability {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_limit, equatable: .init(option), comparable: nil, item: { initialSize, stableId in
                return LimitedRowItem(initialSize, stableId: stableId, availability: limited)
            }))
            entries.append(.sectionId(sectionId, type: .customModern(20)))
            sectionId += 1
        }
    case .premium(let option):
        break
    }
    
    
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().starsGiftPreviewCustomize), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_preview, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return PreviewRowItem(initialSize, stableId: stableId, peer: state.peer, myPeer: state.myPeer, source: state.option, message: state.textState, context: arguments.context, viewType: .firstItem, includeUpgrade: state.includeUpgrade)
    }))
    
    
    let maxTextLength: Int32 = arguments.context.appConfiguration.getGeneralValue("stargifts_message_length_max", orElse: 256)
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_input, equatable: .init(state.textState), comparable: nil, item: { initialSize, stableId in
        return InputTextDataRowItem(initialSize, stableId: stableId, context: arguments.context, state: state.textState, viewType: .lastItem, placeholder: nil, inputPlaceholder: strings().starsGiftPreviewMessagePlaceholder, filter: { text in
            var text = text
            while text.contains("\n\n\n") {
                text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
            }
            
            if !text.isEmpty {
                while text.range(of: "\n")?.lowerBound == text.startIndex {
                    text = String(text[text.index(after: text.startIndex)...])
                }
            }
            return text
        }, updateState: arguments.updateState, limit: maxTextLength, hasEmoji: true)
    }))
    index += 1
    
    
  
    switch state.option {
    case let .starGift(option: gift):
        
        
        if let upgraded = gift.native.generic?.upgradeStars {
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
            
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_upgrade, data: .init(name: strings().giftSendUpgrade(strings().starListItemCountCountable(Int(upgraded))), color: theme.colors.text, type: .switchable(state.includeUpgrade), viewType: .singleItem, action: arguments.toggleUpgrade)))

            entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(strings().giftSendUpgradeInfo(state.peer._asPeer().displayTitle), linkHandler: { _ in
                arguments.previewUpgrade(gift)
            }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1

        }
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_anonymous, data: .init(name: strings().starsGiftPreviewHideMyName, color: theme.colors.text, type: .switchable(state.isAnonymous), viewType: .singleItem, action: arguments.toggleAnonymous)))
        
        let name = state.peer._asPeer().compactDisplayTitle
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().starsGiftPreviewHideMyNameInfo(name, name)), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    case .premium:
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().giftPremiumPreviewInfo(state.peer._asPeer().compactDisplayTitle)), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
        
        
    }
   
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

enum PreviewGiftSource : Equatable {
    case starGift(option: PeerStarGift)
    case premium(option: PremiumGiftProduct)
}

func PreviewStarGiftController(context: AccountContext, option: PreviewGiftSource, peer: EnginePeer) -> InputDataModalController {

    let actionsDisposable = DisposableSet()
    let paymentDisposable = MetaDisposable()
    actionsDisposable.add(paymentDisposable)
    
    let inAppPurchaseManager = context.inAppPurchaseManager
    
    let initialState = State(peer: peer, myPeer: .init(context.myPeer!), option: option, textState: .init())
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var close:(()->Void)? = nil
    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return bestWindow(context, getController?())
        }
    }
    
    actionsDisposable.add(context.starsContext.state.startStrict(next: { state in
        updateState { current in
            var current = current
            current.starsState = state
            return current
        }
    }))

    let arguments = Arguments(context: context, toggleAnonymous: {
        updateState { current in
            var current = current
            current.isAnonymous = !current.isAnonymous
            return current
        }
    }, updateState: { state in
        updateState { current in
            var current = current
            current.textState = state
            return current
        }
    }, toggleUpgrade: {
        updateState { current in
            var current = current
            current.includeUpgrade = !current.includeUpgrade
            return current
        }
    }, previewUpgrade: { gift in
        if let giftId = gift.native.generic?.id {
            _ = showModalProgress(signal: context.engine.payments.starGiftUpgradePreview(giftId: giftId), for: window).startStandalone(next: { attributes in
                showModal(with: StarGift_Nft_Controller(context: context, gift: gift.native, source: .preview(peer, attributes)), for: window)
            })
        }
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().starGiftPreviewTitle)
    
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    
    let buyNonStore:(PremiumGiftProduct)->Void = { premiumProduct in
        let state = stateValue.with { $0 }
        
        let peer = state.peer
        
        let source = BotPaymentInvoiceSource.giftCode(users: [peer.id], currency: premiumProduct.priceCurrencyAndAmount.currency, amount: premiumProduct.priceCurrencyAndAmount.amount, option: .init(users: 1, months: premiumProduct.months, storeProductId: nil, storeQuantity: 0, currency: premiumProduct.priceCurrencyAndAmount.currency, amount: premiumProduct.priceCurrencyAndAmount.amount), text: state.textState.string, entities: state.textState.textInputState().messageTextEntities())
                        
        let invoice = showModalProgress(signal: context.engine.payments.fetchBotPaymentInvoice(source: source), for: context.window)

        actionsDisposable.add(invoice.start(next: { invoice in
            showModal(with: PaymentsCheckoutController(context: context, source: source, invoice: invoice, completion: { status in
                switch status {
                case .paid:
                    PlayConfetti(for: context.window)
                    close?()
                default:
                    break
                }
            }), for: context.window)
        }, error: { error in
            showModalText(for: context.window, text: strings().paymentsInvoiceNotExists)
        }))
        
    }
    
    let buyAppStore:(PremiumGiftProduct)->Void = { premiumProduct in
        
        let state = stateValue.with { $0 }
        
        let peer = state.peer

        guard let storeProduct = premiumProduct.storeProduct else {
            buyNonStore(premiumProduct)
            return
        }
        
        let lockModal = PremiumLockModalController()
        
        var needToShow = true
        delay(0.2, closure: {
            if needToShow {
                showModal(with: lockModal, for: context.window)
            }
        })
        let purpose: AppStoreTransactionPurpose = .giftCode(peerIds: [peer.id], boostPeer: nil, currency: premiumProduct.priceCurrencyAndAmount.currency, amount: premiumProduct.priceCurrencyAndAmount.amount, text: state.textState.string, entities: state.textState.textInputState().messageTextEntities())
        
                
        let _ = (context.engine.payments.canPurchasePremium(purpose: purpose)
        |> deliverOnMainQueue).start(next: { [weak lockModal] available in
            if available {
                paymentDisposable.set((inAppPurchaseManager.buyProduct(storeProduct, quantity: premiumProduct.giftOption.storeQuantity, purpose: purpose)
                |> deliverOnMainQueue).start(next: { [weak lockModal] status in
    
                    lockModal?.close()
                    needToShow = false
                    
                    inAppPurchaseManager.finishAllTransactions()
                    PlayConfetti(for: context.window)
                    close?()
                    
                }, error: { [weak lockModal] error in
                    let errorText: String
                    switch error {
                        case .generic:
                            errorText = strings().premiumPurchaseErrorUnknown
                        case .network:
                            errorText = strings().premiumPurchaseErrorNetwork
                        case .notAllowed:
                            errorText = strings().premiumPurchaseErrorNotAllowed
                        case .cantMakePayments:
                            errorText = strings().premiumPurchaseErrorCantMakePayments
                        case .assignFailed:
                            errorText = strings().premiumPurchaseErrorUnknown
                        case .cancelled:
                            errorText = strings().premiumBoardingAppStoreCancelled
                    }
                    lockModal?.close()
                    showModalText(for: context.window, text: errorText)
                    inAppPurchaseManager.finishAllTransactions()
                }))
            } else {
                lockModal?.close()
                needToShow = false
            }
        })
    }
    
    
    controller.validateData = { _ in
        
        let state = stateValue.with { $0 }
        
        guard let starsState = state.starsState else {
            return .none
        }
        
        switch state.option {
        case let .starGift(option):
            if starsState.balance.value < option.totalStars(state.includeUpgrade) {
                showModal(with: Star_ListScreen(context: context, source: .buy(suffix: nil, amount: option.totalStars(state.includeUpgrade))), for: window)
                return .none
            }
            
            let source: BotPaymentInvoiceSource = .starGift(hideName: state.isAnonymous, includeUpgrade: state.includeUpgrade, peerId: state.peer.id, giftId: option.native.generic!.id, text: state.textState.string, entities: state.textState.textInputState().messageTextEntities())
            
            let paymentForm = context.engine.payments.fetchBotPaymentForm(source: source, themeParams: nil) |> mapToSignal {
                return context.engine.payments.sendStarsPaymentForm(formId: $0.id, source: source) |> mapError { _ in
                    return .generic
                }
            }
            
            _ = showModalProgress(signal: paymentForm, for: context.window).start(next: { result in
                switch result {
                case let .done(receiptMessageId, _, _):
                    PlayConfetti(for: window, stars: true)
                    closeAllModals(window: window)
                    context.bindings.rootNavigation().push(ChatAdditionController(context: context, chatLocation: .peer(peer.id)))
                default:
                    break
                    
                }
            }, error: { error in
                var bp = 0
                bp += 1
            })
        case let .premium(option):
#if APP_STORE
            buyAppStore(option)
#else
            buyNonStore(option)
#endif
        }

        
        
        return .none
    }
    
    let modalInteractions = ModalInteractions(acceptTitle: "", accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    
    controller.afterTransaction = { [weak modalInteractions] _ in
        let state = stateValue.with { $0 }
        let okText: String
        switch option {
        case let .starGift(option):
            okText = strings().starsGiftPreviewSend(strings().starListItemCountCountable(Int(option.totalStars(state.includeUpgrade))))
        case let .premium(option):
            okText = strings().starsGiftPreviewSend(option.price)
        }
        
        modalInteractions?.updateDone { button in
            button.set(text: okText, for: .Normal)
        }
    }
    
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
}


/*

 */



