//
//  GiftOptionsRowItem.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 05.09.2024.
//  Copyright © 2024 Telegram. All rights reserved.
//

import Foundation
import SwiftSignalKit
import TGUIKit
import TelegramCore

struct PremiumPaymentOption : Equatable {
    var title: String
    var desc: String
    var total: String
    var discount: String?
    var months: Int32
    
    var product: PremiumGiftProduct
    var starProduct: PremiumGiftProduct?
    
    var media: LocalAnimatedSticker {
        switch months {
        case 12:
            return LocalAnimatedSticker.premium_gift_12
        case 6:
            return LocalAnimatedSticker.premium_gift_6
        case 3:
            return LocalAnimatedSticker.premium_gift_3
        default:
            return LocalAnimatedSticker.premium_gift_3
        }
    }
    
    var text: NSAttributedString {
        let attr = NSMutableAttributedString()
        attr.append(string: self.title, color: theme.colors.text, font: .medium(.text))
        attr.append(string: "\n")
        attr.append(string: strings().stickersPremium, color: theme.colors.text, font: .normal(.text))
        return attr
    }
}

struct PeerStarGift : Equatable {
    let media: TelegramMediaFile
    let stars: Int64
    let limited: Bool
    let native: StarGift
    
    func totalStars(_ includeUpgrade: Bool, sendMessage: StarsAmount? = nil) -> Int64 {
        if includeUpgrade {
            switch native {
            case let .generic(gift):
                if let upgradeStars = gift.upgradeStars {
                    return stars + upgradeStars + (sendMessage?.value ?? 0)
                }
            default:
                return stars + (sendMessage?.value ?? 0)
            }
        }
        return stars + (sendMessage?.value ?? 0)
    }
}

final class GiftOptionsRowItem : GeneralRowItem {
    
    struct Option {
        enum TypeValue {
            case price(String)
            case stars(Int64)
            case none
        }
        struct Badge {
            let text: String
            let colors: [NSColor]
            let textColor: NSColor
        }
        let file: TelegramMediaFile
        let text: NSAttributedString?
        let type: TypeValue
        let badge: Badge?
        let peer: EnginePeer?
        let invisible: Bool
        let pinned: Bool
        
        var starsPrice: TextViewLayout?
        
        var nativePayment: PremiumPaymentOption?
        var nativeStarGift: PeerStarGift?
        var nativeProfileGift: ProfileGiftsContext.State.StarGift?
        var nativeStarUniqueGift: StarGift.UniqueGift?
        
        var gift: StarGift? {
            return nativeStarUniqueGift.flatMap { .unique($0) } ?? nativeStarGift?.native ?? nativeProfileGift?.gift
        }
        
        static func initialize(_ option: PremiumPaymentOption) -> Option {
            
            var colors: [NSColor] = []
            if theme.colors.isDark {
                colors = [NSColor(0x522124), NSColor(0x653634)]
            } else {
                colors = [theme.colors.redUI.withMultipliedBrightnessBy(1.1), theme.colors.redUI.withMultipliedBrightnessBy(0.9)]
            }
            
            let starsPrice: TextViewLayout?
            if let starOption = option.starProduct {
                let price = NSMutableAttributedString()
                
                price.append(string: strings().giftPremiumPayOrStars(clown + " " + "\(starOption.giftOption.amount)"), color: GOLD, font: .normal(.small))
                price.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)
                
                starsPrice = .init(price)
                starsPrice?.measure(width: .greatestFiniteMagnitude)
            } else {
                starsPrice = nil
            }
            
            return .init(file: option.media.file, text: option.text, type: .price(option.total), badge: option.discount.flatMap { .init(text: $0, colors: colors, textColor: .white )}, peer: nil, invisible: false, pinned: false, starsPrice: starsPrice, nativePayment: option)
        }
        static func initialize(_ option: PeerStarGift) -> Option {
            let badge: Badge?
            
            var redColor: [NSColor] = []
            var blueColor: [NSColor] = []
            
            if theme.colors.isDark {
                redColor = [NSColor(0x522124), NSColor(0x653634)]
                blueColor = [NSColor(0x142e42), NSColor(0x354f5b)]
            } else {
                redColor = [theme.colors.redUI.withMultipliedBrightnessBy(1.1), theme.colors.redUI.withMultipliedBrightnessBy(0.9)]
                blueColor = [theme.colors.accent.withMultipliedBrightnessBy(1.1), theme.colors.accent.withMultipliedBrightnessBy(0.9)]
            }
            
            if let availability = option.native.generic?.availability {
                if availability.remains == 0 {
                    badge = .init(text: strings().giftSoldOut, colors: redColor, textColor: .white)
                } else {
                    badge = .init(text: strings().starGiftLimited, colors: blueColor, textColor: theme.colors.underSelectedColor)
                }
            } else if let unique = option.native.unique {
                badge = .init(text: "\(unique.number)", colors: option.native.backdropColor ?? blueColor, textColor: theme.colors.underSelectedColor)
            } else {
                badge = nil
            }
            return .init(file: option.media, text: nil, type: .stars(option.stars), badge: badge, peer: nil, invisible: false, pinned: false, nativeStarGift: option)
        }
        
        static func initialize(_ option: StarGift.UniqueGift) -> Option {
            return .init(file: option.file!, text: nil, type: .none, badge: nil, peer: nil, invisible: false, pinned: false, nativeStarUniqueGift: option)
        }
        
        
        static func initialize(_ option: ProfileGiftsContext.State.StarGift, transfrarable: Bool = false) -> Option {
            
            var blueColor: [NSColor] = []
            
            if theme.colors.isDark {
                blueColor = [NSColor(0x142e42), NSColor(0x354f5b)]
            } else {
                blueColor = [theme.colors.accent.withMultipliedBrightnessBy(1.1), theme.colors.accent.withMultipliedBrightnessBy(0.9)]
            }
            
            let badge: Badge?
            if let availability = option.gift.generic?.availability {
                badge = .init(text: strings().starTransactionAvailabilityOf(1, Int(availability.total).prettyNumber), colors: blueColor, textColor: theme.colors.underSelectedColor)
            } else if let unique = option.gift.unique {
                badge = .init(text: "\(unique.number)", colors: option.gift.backdropColor ?? blueColor, textColor: theme.colors.underSelectedColor)
            } else {
                badge = nil
            }
            
            let file: TelegramMediaFile
            switch option.gift {
            case .generic(let gift):
                file = gift.file
            case .unique(let uniqueGift):
                file = uniqueGift.file!
            }            
            return .init(file: file, text: nil, type: transfrarable ? .price(strings().starNftTransfer) : .none, badge: badge, peer: option.fromPeer, invisible: !option.savedToProfile, pinned: option.pinnedToTop, nativeProfileGift: option)
        }
        
        var height: CGFloat {
            var height: CGFloat = 0
            switch type {
            case .price:
                height = nativeProfileGift != nil ? 135 : 160
            case .stars:
                height = 135
            case .none:
                height = 100
            }
            if let starsPrice {
                height += starsPrice.layoutSize.height + 10
            }
            return height
        }
    }
    
    fileprivate let options: [Option]
    fileprivate let context: AccountContext
    fileprivate let perRowCount: Int
    fileprivate let fitToSize: Bool
    fileprivate let selected: StarGift?
    
    fileprivate let callback:(Option)->Void
    private let _contextMenu:(Option)->[ContextMenuItem]
    init(_ initialSize: NSSize, stableId: AnyHashable, context: AccountContext, options: [Option], perRowCount: Int = 3, fitToSize: Bool = false, insets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20), viewType: GeneralViewType = .legacy, callback:@escaping(Option)->Void, selected: StarGift? = nil, contextMenu:@escaping(Option)->[ContextMenuItem] = { _ in return [] }) {
        self.options = options
        self.context = context
        self.callback = callback
        self.perRowCount = perRowCount
        self.fitToSize = fitToSize
        self.selected = selected
        self._contextMenu = contextMenu
        assert(!options.isEmpty)
        super.init(initialSize, stableId: stableId, viewType: viewType, inset: insets)
    }
    
    override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        
        let itemSize: NSSize
        if self.fitToSize, self.options.count == 1 {
            itemSize = NSMakeSize(width - self.inset.right - self.inset.left, self.height)
        } else {
            let insets = self.inset
            let count = self.fitToSize ? CGFloat(self.options.count) : 3
            let space = self.width - insets.left - insets.right - (10 * CGFloat(count - 1))
            itemSize = NSMakeSize(floorToScreenPixels(space / count), self.height)
        }
        var x: CGFloat = self.inset.left

        for (i, option) in options.enumerated() {
            if location.x > x && location.x < (x + itemSize.width + 10) {
                return .single(_contextMenu(options[i]))
            }
            x += itemSize.width + 10
        }
        
        
        return .single([])
    }
    
    override var hasBorder: Bool {
        return false
    }
    
    override func viewClass() -> AnyClass {
        return GiftOptionsRowView.self
    }
    
    override var height: CGFloat {
        return options[0].height
    }
}

private final class GiftOptionsRowView:  GeneralContainableRowView {
    
    
    private class OptionView : Control {
        
        
        final class InvisibleView : View {
            private let imageView = ImageView()
            private let visualEffect = VisualEffect()
            required init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                addSubview(visualEffect)
                addSubview(imageView)
                imageView.image = NSImage(resource: .menuEyeSlash).precomposed(theme.colors.text)
                imageView.sizeToFit()
                layer?.cornerRadius = frameRect.height / 2
                visualEffect.bgColor = NSColor.blackTransparent.withAlphaComponent(0.1)
            }
            
            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }
            
            override func layout() {
                super.layout()
                imageView.center()
                visualEffect.frame = bounds
            }
        }
        
        private let sticker = MediaAnimatedStickerView(frame: NSMakeRect(0, 0, 80, 80))
        private var textView: TextView?
        private var badgeView: ImageView?
        private var priceView: PriceView?
        private var starPriceView: StarPriceView?
        private var avatarView: AvatarControl?
        private var invisibleView: InvisibleView?
        private var emoji: PeerInfoSpawnEmojiView?
        private var backgroundView: PeerInfoBackgroundView?
        private var selectionView: View?
        private var starsPrice: InteractiveTextView?
        private var pinnedView: ImageView?


        private class PriceView: View {
            private let textView = TextView()
            required init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                addSubview(textView)
                textView.userInteractionEnabled = false
                textView.isSelectable = false
            }
            
            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }
            
            func update(text: TextViewLayout) {
                self.textView.update(text)
                self.setFrameSize(NSMakeSize(text.layoutSize.width + 16, text.layoutSize.height + 10))
                self.layer?.cornerRadius = frame.height / 2
                self.needsLayout = true
            }
            override func layout() {
                super.layout()
                self.textView.center()
            }
        }
        
        private class StarPriceView: View {
            private let textView = InteractiveTextView()
            private let effect = StarsButtonEffectLayer()
            required init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                addSubview(textView)
                self.layer?.addSublayer(effect)
                textView.userInteractionEnabled = false
                self.layer?.masksToBounds = false
            }
            
            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }
            
            func update(text: TextViewLayout, context: AccountContext) {
                self.textView.set(text: text, context: context)
                self.setFrameSize(NSMakeSize(text.layoutSize.width + 16, text.layoutSize.height + 10))
                self.layer?.cornerRadius = frame.height / 2
                self.layer?.masksToBounds = false
                self.needsLayout = true
                
                
                let rect = self.bounds.insetBy(dx: -5, dy: -5)
                effect.frame = rect
                effect.update(size: rect.size)
            }
            override func layout() {
                super.layout()
                self.textView.center()
            }
        }
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(sticker)
            
            self.layer?.masksToBounds = false
                        
            sticker.userInteractionEnabled = false
            
            backgroundColor = theme.colors.background
            
            layer?.cornerRadius = 10
            
            scaleOnClick = true
            set(handler: { _ in
                
            }, for: .Click)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        var option: GiftOptionsRowItem.Option?
        
        func set(option: GiftOptionsRowItem.Option, context: AccountContext, selected: Bool, animated: Bool, callback:@escaping(GiftOptionsRowItem.Option)->Void) {
            
            self.option = option
            
            self.setSingle(handler: { _ in
                callback(option)
            }, for: .Click)
            
            let parameters = ChatAnimatedStickerMediaLayoutParameters(playPolicy: .framesCount(1), alwaysAccept: true, cache: .temporaryLZ4(.thumb), hidePlayer: false, media: option.file, shimmer: false, thumbAtFrame: 1)
            self.sticker.update(with: option.file, size: self.sticker.frame.size, context: context, table: nil, parameters: parameters, animated: false)
            
            if let text = option.text {
                let current: TextView
                if let view = self.textView {
                    current = view
                } else {
                    current = TextView()
                    self.addSubview(current)
                    self.textView = current
                    current.userInteractionEnabled = false
                    current.isSelectable = false
                }
                let textLayout = TextViewLayout(text, alignment: .center)
                textLayout.measure(width: .greatestFiniteMagnitude)
                current.update(textLayout)
            } else if let view = self.textView {
                performSubviewRemoval(view, animated: false)
                self.textView = nil
            }
            
            if let peer = option.peer {
                let current: AvatarControl
                if let view = self.avatarView {
                    current = view
                } else {
                    current = AvatarControl(font: .avatar(8))
                    current.setFrameSize(20, 20)
                    self.addSubview(current)
                    self.avatarView = current
                    current.userInteractionEnabled = false
                }
                current.setPeer(account: context.account, peer: peer._asPeer())
            } else if let avatarView {
                performSubviewRemoval(avatarView, animated: false)
                self.avatarView = nil
            }
            
            switch option.type {
            case .price(let string):
                
                if let view = self.starPriceView {
                    performSubviewRemoval(view, animated: false)
                    self.starPriceView = nil
                }
                
                let current: PriceView
                if let view = self.priceView {
                    current = view
                } else {
                    current = PriceView(frame: .zero)
                    self.addSubview(current)
                    self.priceView = current
                }
                let priceLayout = TextViewLayout(.initialize(string: string, color: option.gift?.unique != nil ? .white : theme.colors.accent, font: .medium(.text)))
                priceLayout.measure(width: .greatestFiniteMagnitude)
                current.backgroundColor = option.gift?.unique != nil ? NSColor.white.withAlphaComponent(0.2) : theme.colors.accent.withAlphaComponent(0.2)
                current.update(text: priceLayout)
                
            case .stars(let int64):
                if let view = self.priceView {
                    performSubviewRemoval(view, animated: false)
                    self.priceView = nil
                }
                
                let current: StarPriceView
                if let view = self.starPriceView {
                    current = view
                } else {
                    current = StarPriceView(frame: .zero)
                    self.addSubview(current)
                    self.starPriceView = current
                }
                let attr = NSMutableAttributedString()
                attr.append(string: "\(clown_space)\(int64)", color: GOLD, font: .medium(.text))
                attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)
                let priceLayout = TextViewLayout(attr)
                priceLayout.measure(width: .greatestFiniteMagnitude)
                current.backgroundColor = GOLD.withAlphaComponent(0.2)
                current.update(text: priceLayout, context: context)
            case .none:
                if let view = self.priceView {
                    performSubviewRemoval(view, animated: false)
                    self.priceView = nil
                }
                if let view = self.starPriceView {
                    performSubviewRemoval(view, animated: false)
                    self.starPriceView = nil
                }
            }
            
            if let badge = option.badge {
                let current: ImageView
                if let view = self.badgeView {
                    current = view
                } else {
                    current = ImageView()
                    addSubview(current, positioned: .above, relativeTo: self.sticker)
                    self.badgeView = current
                }
                                
                let ribbon = generateGradientTintedImage(image: NSImage(named: "GiftRibbon")?.precomposed(), colors: badge.colors, direction: .diagonal)!
                
                
                current.image = generateGiftBadgeBackground(background: ribbon, text: badge.text, textColor: badge.textColor)
                
                current.sizeToFit()
            } else if let view = badgeView {
                performSubviewRemoval(view, animated: false)
                self.badgeView = nil
            }

            
            if option.invisible {
                let current: InvisibleView
                if let view = self.invisibleView {
                    current = view
                } else {
                    current = InvisibleView(frame: NSMakeRect(0, 0, 30, 30))
                    addSubview(current)
                    self.invisibleView = current
                }
            } else if let view = self.invisibleView {
                performSubviewRemoval(view, animated: false)
                self.invisibleView = nil
            }
            
            
            if let uniqueGift = option.gift?.unique {
                do {
                    let current:PeerInfoBackgroundView
                    if let view = self.backgroundView {
                        current = view
                    } else {
                        current = PeerInfoBackgroundView(frame: bounds)
                        self.addSubview(current, positioned: .below, relativeTo: sticker)
                        self.backgroundView = current
                    }
                    var colors: [NSColor] = []

                    for attribute in uniqueGift.attributes {
                        switch attribute {
                        case let .backdrop(_, innerColor, outerColor, _, _, _):
                            colors = [NSColor(UInt32(innerColor)), NSColor(UInt32(outerColor))]
                        default:
                            break
                        }
                    }
                    current.gradient = colors
                }
                do {
                    let current:PeerInfoSpawnEmojiView
                    if let view = self.emoji {
                        current = view
                    } else {
                        current = PeerInfoSpawnEmojiView(frame: bounds)
                        self.addSubview(current, positioned: .below, relativeTo: sticker)
                        self.emoji = current
                    }
                    
                    var patternFile: TelegramMediaFile?
                    var patternColor: NSColor?

                    for attribute in uniqueGift.attributes {
                        switch attribute {
                        case .pattern(_, let file, _):
                            patternFile = file
                        case let .backdrop(_, _, _, color, _, _):
                            patternColor = NSColor(UInt32(color)).withAlphaComponent(0.4)
                        default:
                            break
                        }
                    }
                    if let patternFile, let patternColor {
                        current.set(fileId: patternFile.fileId.id, color: patternColor, context: context, animated: false)
                        current.fraction = 0.66
                    }
                }
                
            } else {
                if let view = self.emoji {
                    performSubviewRemoval(view, animated: false)
                    self.emoji = nil
                }
                if let view = self.backgroundView {
                    performSubviewRemoval(view, animated: false)
                    self.backgroundView = nil
                }
            }
            
            if option.pinned {
                let current: ImageView
                if let view = self.pinnedView {
                    current = view
                } else {
                    current = ImageView()
                    self.pinnedView = current
                    addSubview(current)
                }
                current.image = NSImage(resource: .iconChatListPinned).precomposed(.white)
                current.sizeToFit()
            } else if let view = self.pinnedView {
                performSubviewRemoval(view, animated: animated)
                self.pinnedView = nil
            }
            
            
            if let starsPrice = option.starsPrice {
                let current: InteractiveTextView
                if let view = self.starsPrice {
                    current = view
                } else {
                    current = InteractiveTextView()
                    current.userInteractionEnabled = false
                    self.starsPrice = current
                    addSubview(current)
                }
                current.set(text: starsPrice, context: context)
            } else if let view = self.starsPrice {
                performSubviewRemoval(view, animated: animated)
                self.starsPrice = nil
            }
            
            if selected {
                let current: View
                if let view = selectionView {
                    current = view
                } else {
                    current = View()
                    addSubview(current)
                    self.selectionView = current
                    current.layer?.cornerRadius = 10
                }
                current.layer?.borderColor = theme.colors.background.cgColor
                current.layer?.borderWidth = 3
                
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            } else if let selectionView {
                performSubviewRemoval(selectionView, animated: animated)
                self.selectionView = nil
            }
            
            
            needsLayout = true
        }
        
        override func layout() {
            super.layout()
            sticker.centerX(y: priceView != nil ? 0 : 10)
            textView?.centerX(y: sticker.frame.maxY + 5)
            if let badgeView {
                badgeView.setFrameOrigin(frame.width - badgeView.frame.width, 0)
            }
            var offset: CGFloat = 0
            if let starsPrice {
                starsPrice.centerX(y: frame.height - starsPrice.frame.height - 10)
                offset += starsPrice.frame.height + 10
            }
            
            if let priceView {
                priceView.centerX(y: frame.height - priceView.frame.height - 10 - offset)
            }
            if let starPriceView {
                starPriceView.centerX(y: frame.height - starPriceView.frame.height - 10 - offset)
            }
            if let avatarView {
                avatarView.setFrameOrigin(NSMakePoint(4, 4))
            }
            if let backgroundView {
                backgroundView.frame = bounds
            }
            if let emoji {
                emoji.frame = bounds.offsetBy(dx: 0, dy: 20)
            }
            
            if let pinnedView {
                pinnedView.setFrameOrigin(NSMakePoint(4, 4))
            }
           
            invisibleView?.center()
            
            if let selectionView {
                selectionView.frame = bounds.insetBy(dx: 3, dy: 3)
            }
        }
    }
    
    private let content = View()
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(content)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        
        guard let item = item as? GiftOptionsRowItem else {
            return
        }
                
        
        let itemSize: NSSize
        if item.fitToSize, item.options.count == 1 {
            itemSize = NSMakeSize(content.frame.width - item.inset.right - item.inset.left, content.frame.height)
        } else {
            let insets = item.inset
            let count = item.fitToSize ? CGFloat(item.options.count) : 3
            let space = content.frame.width - insets.left - insets.right - (10 * CGFloat(count - 1))
            itemSize = NSMakeSize(floorToScreenPixels(space / count), content.frame.height)
        }

        while self.content.subviews.count > item.options.count {
            self.content.subviews.last?.removeFromSuperview()
        }
        while self.content.subviews.count < item.options.count {
            self.content.addSubview(OptionView(frame: itemSize.bounds))
        }
        
        layout()
        
        for (i, subview) in content.subviews.enumerated() {
            let view = subview as? OptionView
            if view?.option?.nativeStarGift?.native.generic?.id != item.options[i].nativeStarGift?.native.generic?.id {
                if animated {
                    view?.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.35)
                }
            }
            view?.set(option: item.options[i], context: item.context, selected: item.options[i].gift == item.selected && item.selected != nil, animated: animated, callback: item.callback)
        }
        
    }
    
    override var backdorColor: NSColor {
        guard let item = item as? GiftOptionsRowItem else {
            return .clear
        }
        return item.viewType == .legacy ? .clear : super.backdorColor
    }
    
    override func layout() {
        super.layout()
        
        guard let item = item as? GiftOptionsRowItem else {
            return
        }
        
        content.frame = containerView.bounds
        
        let itemSize: NSSize
        if item.fitToSize, item.options.count == 1 {
            itemSize = NSMakeSize(content.frame.width - item.inset.right - item.inset.left, content.frame.height)
        } else {
            let insets = item.inset
            let count = item.fitToSize ? CGFloat(item.options.count) : 3
            let space = content.frame.width - insets.left - insets.right - (10 * CGFloat(count - 1))
            itemSize = NSMakeSize(floorToScreenPixels(space / count), content.frame.height)
        }
        var x: CGFloat = item.inset.left

        for (i, subview) in content.subviews.enumerated() {
            let view = subview as? OptionView
            view?.setFrameSize(itemSize)
            subview.setFrameOrigin(x, 0)
            x += subview.frame.width + 10
        }
    }
}
