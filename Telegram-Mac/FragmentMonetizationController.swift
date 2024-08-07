//
//  FragmentMonetizationController.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 07.03.2024.
//  Copyright © 2024 Telegram. All rights reserved.
//

import Foundation
import TelegramCore
import Postbox
import TGUIKit
import SwiftSignalKit
import CurrencyFormat
import InputView
import GraphCore


private final class TransactionTypesItem : GeneralRowItem {
    fileprivate let context: AccountContext
    fileprivate let items: [ScrollableSegmentItem]
    fileprivate let callback:(State.TransactionMode)->Void
    init(_ initialSize: NSSize, stableId: AnyHashable, context: AccountContext, modes: [State.TransactionMode], transactionMode: State.TransactionMode, viewType: GeneralViewType, callback:@escaping(State.TransactionMode)->Void) {
        self.context = context
        self.callback = callback
        
        let theme = ScrollableSegmentTheme(background: .clear, border: .clear, selector: theme.colors.accent, inactiveText: theme.colors.grayText, activeText: theme.colors.text, textFont: .normal(.text))
        
        var items: [ScrollableSegmentItem] = []
        
        for mode in modes {
            items.append(.init(title: mode.text, index: mode.rawValue, uniqueId: Int32(mode.rawValue), selected: transactionMode == mode, insets: NSEdgeInsets(left: 10, right: 10), icon: nil, theme: theme, equatable: UIEquatable(mode)))
        }
        
        self.items = items
        super.init(initialSize, height: 50, stableId: stableId, viewType: viewType)
    }
    
    override func viewClass() -> AnyClass {
        return TransactionTypesView.self
    }
}

private final class TransactionTypesView: GeneralContainableRowView {
    fileprivate let segmentControl: ScrollableSegmentView
    required init(frame frameRect: NSRect) {
        self.segmentControl = ScrollableSegmentView(frame: NSMakeRect(0, 0, frameRect.width, 50))
        super.init(frame: frameRect)
        addSubview(segmentControl)
        
        segmentControl.didChangeSelectedItem = { [weak self] selected in
            if let item = self?.item as? TransactionTypesItem {
                if selected.uniqueId == 0 {
                    item.callback(.ton)
                } else if selected.uniqueId == 1 {
                    item.callback(.xtr)
                }
            }
        }
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? TransactionTypesItem else {
            return
        }
        segmentControl.updateItems(item.items, animated: animated)
        needsLayout = true
    }
    
    override func layout() {
        segmentControl.frame = containerView.bounds
    }
}

private final class TransactionPreviewRowItem : GeneralRowItem {
    
    let amountLayout: TextViewLayout
    let dateLayout: TextViewLayout
    let channelLayout: TextViewLayout?
    let peer: EnginePeer?
    let context: AccountContext
    init(_ initialSize: NSSize, stableId: AnyHashable, transaction: State.Transaction, peer: EnginePeer?, context: AccountContext, viewType: GeneralViewType) {
        
        self.peer = peer
        self.context = context
        let amountAttr = NSMutableAttributedString()
        let justAmount = NSAttributedString.initialize(string: formatCurrencyAmount(transaction.amount, currency: TON).prettyCurrencyNumber, color: theme.colors.text, font: .medium(25)).smallDecemial
        amountAttr.append(justAmount)
        amountAttr.append(string: " \(TON)", color: theme.colors.text, font: .medium(25))
        switch transaction.source {
        case .incoming, .refund:
            amountAttr.insert(.initialize(string: "+", font: .medium(25)), at: 0)
            amountAttr.addAttribute(.foregroundColor, value: theme.colors.greenUI, range: amountAttr.range)
        case .withdraw:
            amountAttr.addAttribute(.foregroundColor, value: theme.colors.redUI, range: amountAttr.range)
        }
        
        self.amountLayout = .init(amountAttr)
        self.amountLayout.measure(width: .greatestFiniteMagnitude)
        
        let formatter = DateSelectorUtil.mediaFileDate

        
        let statusAttr = NSMutableAttributedString()
        
        switch transaction.source {
        case let .incoming(fromDate, toDate):
            statusAttr.append(string: formatter.string(from: Date(timeIntervalSince1970: TimeInterval(fromDate))) + " - " + formatter.string(from: Date(timeIntervalSince1970: TimeInterval(toDate))), color: theme.colors.grayText, font: .normal(.title))
        default:
            statusAttr.append(string: stringForFullDate(timestamp: transaction.date), color: theme.colors.grayText, font: .normal(.title))
        }
        
        self.dateLayout = .init(statusAttr)
        self.dateLayout.measure(width: .greatestFiniteMagnitude)
        
        if let _ = peer {
            let channelLayout: TextViewLayout = .init(.initialize(string: strings().monetizationTransactionInfoProceeds, color: theme.colors.text, font: .medium(.text)))
            channelLayout.measure(width: .greatestFiniteMagnitude)
            self.channelLayout = channelLayout
        } else {
            var string: String?
            
            
            switch transaction.source {
            case let .withdraw(provider, status, _):
                switch status {
                case .failed:
                    string = strings().monetizationTransactionFailed
                case .pending:
                    string = strings().monetizationTransactionPending
                case .success:
                    string = strings().monetizationTransactionWithdrawal(provider)
                }
            case .refund:
                string = strings().monetizationTransactionRefund
            case .incoming:
                break
            }
            if let string {
                let channelLayout: TextViewLayout = .init(.initialize(string: string, color: theme.colors.text, font: .medium(.text)))
                channelLayout.measure(width: .greatestFiniteMagnitude)
                self.channelLayout = channelLayout
            } else {
                self.channelLayout = nil
            }
        }
        
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }
    
    override var height: CGFloat {
        var height = amountLayout.layoutSize.height + self.dateLayout.layoutSize.height + 2
        
        if let channelLayout = channelLayout {
            height += 20 + channelLayout.layoutSize.height
        }
        if let _ = peer {
            height += 30 + 10
        }
        
        return height
    }
    
    
    override func viewClass() -> AnyClass {
        return TransactionPreviewRowView.self
    }
}

private final class TransactionPreviewRowView : GeneralContainableRowView {
    private let textView = TextView()
    private let dateView = TextView()
    private var procced: TextView?
    private var channel: ChannelView?

    private class ChannelView : Control {
        private let avatar = AvatarControl(font: .avatar(12))
        private let textView = TextView()
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(avatar)
            addSubview(textView)
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            avatar.setFrameSize(NSMakeSize(30, 30))
            scaleOnClick = true
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(_ peer: Peer, context: AccountContext, presentation: TelegramPresentationTheme, maxWidth: CGFloat) {
            self.avatar.setPeer(account: context.account, peer: peer)
            
            let layout = TextViewLayout(.initialize(string: peer.displayTitle, color: presentation.colors.text, font: .medium(.text)))
            layout.measure(width: maxWidth - 40)
            textView.update(layout)
            self.backgroundColor = presentation.colors.listBackground
            
            self.setFrameSize(NSMakeSize(layout.layoutSize.width + 10 + avatar.frame.width + 10, 30))
            
            self.layer?.cornerRadius = frame.height / 2
        }
        
        override func layout() {
            super.layout()
            textView.centerY(x: avatar.frame.maxX + 10)
        }
    }
    
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        
        addSubview(dateView)
        
        dateView.userInteractionEnabled = false
        dateView.isSelectable = false
        

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        textView.centerX(y: 0)
        dateView.centerX(y: textView.frame.maxY + 2)
        if let procced {
            procced.centerX(y: dateView.frame.maxY + 20)
            if let channel {
                channel.centerX(y: procced.frame.maxY + 10)
            }
        }
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? TransactionPreviewRowItem else {
            return
        }
        
        self.textView.update(item.amountLayout)
        self.dateView.update(item.dateLayout)
        
        if let channelLayout = item.channelLayout {
            let current: TextView
            if let view = self.procced {
                current = view
            } else {
                current = TextView()
                self.procced = current
                addSubview(current)
                current.userInteractionEnabled = false
                current.isSelectable = false
            }
            current.update(channelLayout)
        } else if let view = self.procced {
            performSubviewRemoval(view, animated: animated)
            self.procced = nil
        }
        
        if let peer = item.peer {
            let current: ChannelView
            if let view = self.channel {
                current = view
            } else {
                current = ChannelView(frame: .zero)
                self.channel = current
                addSubview(current)
            }
            current.update(peer._asPeer(), context: item.context, presentation: theme, maxWidth: frame.width - 60)
        } else if let view = self.channel {
            performSubviewRemoval(view, animated: animated)
            self.channel = nil
        }
    }
}


private func insertSymbolIntoMiddle(of string: String, with symbol: Character) -> String {
    var modifiedString = string
    let middleIndex = modifiedString.index(modifiedString.startIndex, offsetBy: modifiedString.count / 2)
    modifiedString.insert(contentsOf: [symbol], at: middleIndex)
    return modifiedString
}



extension String {
    var prettyCurrencyNumber: String {
        let nsString = self as NSString
        let range = nsString.range(of: ".")
        var string = self
        if range.location != NSNotFound {
            var lastIndex = self.count - 1
            while lastIndex > range.location && (self[self.index(self.startIndex, offsetBy: lastIndex)] == "0" || self[self.index(self.startIndex, offsetBy: lastIndex)] == "." || lastIndex > range.location + 4) {
                lastIndex -= 1
            }
            string = String(self.prefix(lastIndex + 1))
        }
        if string.hasSuffix(".") {
            _ = string.removeLast()
        }
        return string
    }
    var prettyCurrencyNumberUsd: String {
        let nsString = self as NSString
        let range = nsString.range(of: ".")
        var string = self
        if range.location != NSNotFound {
            var lastIndex = self.count - 1
            while lastIndex > range.location && (self[self.index(self.startIndex, offsetBy: lastIndex)] == "0" || self[self.index(self.startIndex, offsetBy: lastIndex)] == "." || lastIndex > range.location + 2) {
                lastIndex -= 1
            }
            string = String(self.prefix(lastIndex + 1))
        }
        if string.hasSuffix(".") {
            _ = string.removeLast()
        }
        return string
    }
}


extension StarsContext.State {
    var usdRate: Double {
        return 0.01
    }
    var fractional: Double {
        return currencyToFractionalAmount(value: balance, currency: XTR) ?? 0
    }
    var usdAmount: String {
        return "$" + "\(self.fractional * self.usdRate)".prettyCurrencyNumberUsd
    }
    
}


private final class TransactionRowItem : GeneralRowItem {
    let context: AccountContext
    let transaction: State.Transaction
    let title: TextViewLayout
    let address: TextViewLayout?
    let date: TextViewLayout
    let amount: TextViewLayout
    init(_ initialSize: NSSize, stableId: AnyHashable, context: AccountContext, transaction: State.Transaction, viewType: GeneralViewType, action: @escaping()->Void) {
        self.context = context
        self.transaction = transaction
        
        let titleText: String
        switch transaction.source {
        case .incoming:
            titleText = strings().monetizationTransactionProceeds
        case let .withdraw(provider, _, _):
            titleText = strings().monetizationTransactionWithdrawal(provider)
        case .refund:
            titleText = strings().monetizationTransactionRefund
        }
        
        self.title = .init(.initialize(string: titleText, color: theme.colors.text, font: .normal(.title)), maximumNumberOfLines: 1)
        
        self.address = nil
        
        let statusAttr = NSMutableAttributedString()
        
        let formatter = DateSelectorUtil.mediaFileDate
        
        switch transaction.source {
        case .incoming(let fromDate, let toDate):
            statusAttr.append(string: formatter.string(from: Date(timeIntervalSince1970: TimeInterval(fromDate))) + " - " + formatter.string(from: Date(timeIntervalSince1970: TimeInterval(toDate))), color: theme.colors.grayText, font: .normal(.title))
        default:
            statusAttr.append(string: stringForFullDate(timestamp: transaction.date), color: theme.colors.grayText, font: .normal(.text))
        }
        
        switch transaction.source {
        case let .withdraw(_, status, _):
            switch status {
            case .failed:
                statusAttr.append(string: " — " + strings().monetizationTransactionFailed, color: theme.colors.grayText, font: .normal(.text))
                statusAttr.addAttribute(.foregroundColor, value: theme.colors.redUI, range: statusAttr.range)
            case .pending:
                statusAttr.append(string: " — " + strings().monetizationTransactionPending, color: theme.colors.grayText, font: .normal(.text))
                statusAttr.addAttribute(.foregroundColor, value: theme.colors.accent, range: statusAttr.range)
            case .success:
                break
            }
        case .refund, .incoming:
            break
        }
        
        self.date = .init(statusAttr, maximumNumberOfLines: 1)
        
        let amountAttr = NSMutableAttributedString()
        let justAmount = NSAttributedString.initialize(string: formatCurrencyAmount(transaction.amount, currency: "TON").prettyCurrencyNumber, color: theme.colors.text, font: .medium(.header)).smallDecemial
        amountAttr.append(justAmount)
        switch transaction.source {
        case .incoming, .refund:
            amountAttr.insert(.initialize(string: "+", font: .medium(.header)), at: 0)
            amountAttr.addAttribute(.foregroundColor, value: theme.colors.greenUI, range: amountAttr.range)
            amountAttr.append(string: " ")
            amountAttr.append(.embeddedAnimated(LocalAnimatedSticker.ton_logo.file, color: theme.colors.greenUI))
        case .withdraw:
            amountAttr.addAttribute(.foregroundColor, value: theme.colors.redUI, range: amountAttr.range)
            amountAttr.append(string: " ")
            amountAttr.append(.embeddedAnimated(LocalAnimatedSticker.ton_logo.file, color: theme.colors.redUI))
        }
        
        self.amount = .init(amountAttr)
        
        
        super.init(initialSize, stableId: stableId, viewType: viewType, action: action)
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.amount.measure(width: blockWidth)
        self.title.measure(width: blockWidth - self.amount.layoutSize.width - viewType.innerInset.left - viewType.innerInset.right)
        self.date.measure(width: blockWidth - self.amount.layoutSize.width - viewType.innerInset.left - viewType.innerInset.right)
        self.address?.measure(width: blockWidth - self.amount.layoutSize.width - viewType.innerInset.left - viewType.innerInset.right)

        return true
    }
    
    override func viewClass() -> AnyClass {
        return TransactioRowView.self
    }
    
    override var height: CGFloat {
        var height: CGFloat = 0
        
        height += viewType.innerInset.top
        height += title.layoutSize.height
        height += 3
        if let address {
            height += address.layoutSize.height
            height += 3
        }
        height += date.layoutSize.height
        
        height += viewType.innerInset.bottom
        return height
    }
}

private final class TransactioRowView : GeneralContainableRowView {
    private let titleView = TextView()
    private let dateView = TextView()
    private let amountView = InteractiveTextView(frame: .zero)
    private var addressView: TextView?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(titleView)
        addSubview(dateView)
        addSubview(amountView)
        
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        
        dateView.userInteractionEnabled = false
        dateView.isSelectable = false
        
        amountView.userInteractionEnabled = false
       // amountView.isSelectable = false
        
        containerView.set(handler: { [weak self] _ in
            self?.updateColors()
        }, for: .Highlight)
        containerView.set(handler: { [weak self] _ in
            self?.updateColors()
        }, for: .Normal)
        containerView.set(handler: { [weak self] _ in
            self?.updateColors()
        }, for: .Hover)
        
        containerView.set(handler: { [weak self] _ in
            if let item = self?.item as? GeneralRowItem {
                item.action()
            }
        }, for: .Click)
    }
    
    override func updateColors() {
        super.updateColors()
        if let item = item as? GeneralRowItem {
            self.background = item.viewType.rowBackground
            let highlighted = isSelect ? self.backdorColor : theme.colors.grayHighlight
            containerView.set(background: self.backdorColor, for: .Normal)
            containerView.set(background: highlighted, for: .Highlight)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        
        guard let item = item as? TransactionRowItem else {
            return
        }
        
        titleView.setFrameOrigin(NSMakePoint(item.viewType.innerInset.left, item.viewType.innerInset.top))
        
        var dateY: CGFloat = titleView.frame.maxY + 3
        if let addressView {
            addressView.setFrameOrigin(NSMakePoint(titleView.frame.minX, titleView.frame.maxY + 3))
            dateY = addressView.frame.maxY + 3
        }
        dateView.setFrameOrigin(NSMakePoint(titleView.frame.minX, dateY))
        
        amountView.centerY(x: containerView.frame.width - amountView.frame.width - item.viewType.innerInset.right)
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? TransactionRowItem else {
            return
        }
        
        titleView.update(item.title)
        amountView.set(text: item.amount, context: item.context)
        dateView.update(item.date)
        
        if let address = item.address {
            let current: TextView
            if let view = self.addressView {
                current = view
            } else {
                current = TextView()
                current.userInteractionEnabled = false
                current.isSelectable = false
                addSubview(current)
                self.addressView = current
            }
            current.update(address)
        } else if let view = self.addressView {
            performSubviewRemoval(view, animated: animated)
            self.addressView = nil
        }
        
        needsLayout = true
    }
}


private final class Arguments {
    let context: AccountContext
    let interactions: TextView_Interactions
    let updateState:(Updated_ChatTextInputState)->Void
    let executeLink:(String)->Void
    let withdraw:()->Void
    let promo:()->Void
    let loadDetailedGraph:(StatsGraph, Int64) -> Signal<StatsGraph?, NoError>
    let transaction:(State.Transaction)->Void
    let toggleAds:()->Void
    let loadMore:()->Void
    let toggleTransactionType:(State.TransactionMode)->Void
    let openStarsTransaction:(Star_Transaction)->Void
    init(context: AccountContext, interactions: TextView_Interactions, updateState:@escaping(Updated_ChatTextInputState)->Void, executeLink:@escaping(String)->Void, withdraw:@escaping()->Void, promo: @escaping()->Void, loadDetailedGraph:@escaping(StatsGraph, Int64) -> Signal<StatsGraph?, NoError>, transaction:@escaping(State.Transaction)->Void, toggleAds:@escaping()->Void, loadMore:@escaping()->Void, toggleTransactionType:@escaping(State.TransactionMode)->Void, openStarsTransaction:@escaping(Star_Transaction)->Void) {
        self.context = context
        self.interactions = interactions
        self.updateState = updateState
        self.executeLink = executeLink
        self.withdraw = withdraw
        self.promo = promo
        self.loadDetailedGraph = loadDetailedGraph
        self.transaction = transaction
        self.toggleAds = toggleAds
        self.loadMore = loadMore
        self.toggleTransactionType = toggleTransactionType
        self.openStarsTransaction = openStarsTransaction
    }
}


private struct State : Equatable {

    enum TransactionMode : Int {
        case ton = 0
        case xtr = 1
        
        var text: String {
            switch self {
            case .xtr:
                return strings().monetizationTransactionsStars
            case .ton:
                return strings().monetizationTransactionsTON
            }
        }
    }
    
    struct Transaction : Equatable {
        enum Source : Equatable {
            case incoming(fromDate: Int32, toDate: Int32)
            case withdraw(provider: String, status: Status, url: String?)
            case refund(provider: String)
        }
        enum Status : Equatable {
            case success
            case failed
            case pending
        }
        let date: Int32
        let source: Source
        let amount: Int64
    }
    struct Balance : Equatable {
        var ton: Int64
        var usdRate: Double
        
        var fractional: Double {
            return currencyToFractionalAmount(value: ton, currency: "TON") ?? 0
        }
        
        var usd: String {
            return "$" + "\(self.fractional * self.usdRate)".prettyCurrencyNumberUsd
        }
    }
    struct Overview : Equatable {
        var balance: Balance
        var last: Balance
        var all: Balance
    }
    
    var config_withdraw: Bool
    
    
    var overview: Overview = .init(balance: .init(ton: 0, usdRate: 0), last: .init(ton: 0, usdRate: 0), all: .init(ton: 0, usdRate: 0))
    var balance: Balance = .init(ton: 0, usdRate: 0)
    var transactions: [Transaction] = []
    var transactionsState: RevenueStatsTransactionsContext.State?
    
    
    var withdrawError: RequestRevenueWithdrawalError? = nil
    
    var peer: EnginePeer? = nil
    
    var canWithdraw: Bool {
        return (peer?._asPeer().groupAccess.isCreator ?? false) && config_withdraw
    }
    
    var revenueGraph: StatsGraph?
    var topHoursGraph: StatsGraph?
    
    
    var status: ChannelBoostStatus?
    var myStatus: MyBoostStatus?
    
    var adsRestricted: Bool = false
    
    var transactionMode: TransactionMode = .ton
    
}

private func _id_overview(_ index: Int) -> InputDataIdentifier {
    return InputDataIdentifier("_id_overview_\(index)")
}
private func _id_transaction(_ index: Int) -> InputDataIdentifier {
    return InputDataIdentifier("_id_transaction\(index)")
}

private func _id_transaction(_ transaction: Star_Transaction) -> InputDataIdentifier {
    return InputDataIdentifier("_id_transaction_\(transaction.id)_\(transaction.type)")
}


private let _id_balance = InputDataIdentifier("_id_balance")

private let _id_top_hours_graph = InputDataIdentifier("_id_top_hours_graph")
private let _id_revenue_graph = InputDataIdentifier("_id_revenue_graph")

private let _id_switch_ad = InputDataIdentifier("_id_switch_ad")

private let _id_loading = InputDataIdentifier("_id_loading")
private let _id_load_more = InputDataIdentifier("_id_load_more")

private let _id_transaction_mode = InputDataIdentifier("_id_transaction_mode")


private func entries(_ state: State, arguments: Arguments, detailedDisposable: DisposableDict<InputDataIdentifier>) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
        
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(strings().monetizationHeader("%"), linkHandler: { _ in
        arguments.promo()
    }), data: .init(color: theme.colors.listGrayText, viewType: .singleItem)))
    index += 1
    
    
    do {
        
        struct Graph {
            let graph: StatsGraph
            let title: String
            let identifier: InputDataIdentifier
            let type: ChartItemType
            let rate: Double
            let load:(InputDataIdentifier)->Void
        }
        
        var graphs: [Graph] = []
        if let graph = state.topHoursGraph, !graph.isEmpty {
            graphs.append(Graph(graph: graph, title: strings().monetizationImpressionsTitle, identifier: _id_top_hours_graph, type: .hourlyStep, rate: 1.0, load: { identifier in
               
            }))
        }
        if let graph = state.revenueGraph, !graph.isEmpty {
            graphs.append(Graph(graph: graph, title: strings().monetizationAdRevenueTitle, identifier: _id_revenue_graph, type: .currency(TON), rate: state.balance.usdRate, load: { identifier in
                
            }))
        }
        
        
        for graph in graphs {
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(graph.title), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1
            
            switch graph.graph {
            case let .Loaded(_, string):
                ChartsDataManager.readChart(data: string.data(using: .utf8)!, sync: true, success: { collection in
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: graph.identifier, equatable: InputDataEquatable(graph.graph), comparable: nil, item: { initialSize, stableId in
                        return StatisticRowItem(initialSize, stableId: stableId, context: arguments.context, collection: collection, viewType: .singleItem, type: graph.type, rate: graph.rate, getDetailsData: { date, completion in
                            detailedDisposable.set(arguments.loadDetailedGraph(graph.graph, Int64(date.timeIntervalSince1970) * 1000).start(next: { graph in
                                if let graph = graph, case let .Loaded(_, data) = graph {
                                    completion(data)
                                }
                            }), forKey: graph.identifier)
                        })
                    }))
                }, failure: { error in
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: graph.identifier, equatable: InputDataEquatable(graph.graph), comparable: nil, item: { initialSize, stableId in
                        return StatisticLoadingRowItem(initialSize, stableId: stableId, error: error.localizedDescription)
                    }))
                })
                                
                index += 1
            case .OnDemand:
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: graph.identifier, equatable: InputDataEquatable(graph.graph), comparable: nil, item: { initialSize, stableId in
                    return StatisticLoadingRowItem(initialSize, stableId: stableId, error: nil)
                }))
                index += 1
//                if !uiState.loading.contains(graph.identifier) {
//                    graph.load(graph.identifier)
//                }
            case let .Failed(error):
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: graph.identifier, equatable: InputDataEquatable(graph.graph), comparable: nil, item: { initialSize, stableId in
                    return StatisticLoadingRowItem(initialSize, stableId: stableId, error: error)
                }))
                index += 1
               // updateIsLoading(graph.identifier, false)
            case .Empty:
                break
            }
        }
        
    }
    
    do {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
        struct Tuple : Equatable {
            let overview: Fragment_OverviewRowItem.Overview
            let viewType: GeneralViewType
        }
        
        let tuples: [Tuple] = [
            .init(overview: .init(amount: state.overview.balance.ton, usdAmount: state.overview.balance.usd, info: strings().monetizationOverviewAvailable, stars: nil), viewType: .firstItem),
                               .init(overview: .init(amount: state.overview.all.ton, usdAmount: state.overview.all.usd, info: strings().monetizationOverviewTotal, stars: nil), viewType: .lastItem)
        ]
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().monetizationOverviewTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        
        for (i, tuple) in tuples.enumerated() {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_overview(i), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
                return Fragment_OverviewRowItem(initialSize, stableId: stableId, context: arguments.context, overview: tuple.overview, currency: .ton, viewType: tuple.viewType)
            }))
        }
    }
    
    
    if state.balance.ton > 0 {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
      
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().monetizationBalanceTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_balance, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return Fragment_BalanceRowItem(initialSize, stableId: stableId, context: arguments.context, balance: .init(amount: state.balance.ton, usd: state.balance.usd, currency: .ton), canWithdraw: state.canWithdraw, viewType: .singleItem, transfer: arguments.withdraw)
        }))
        
        let text: String
        if state.config_withdraw {
            text = strings().monetizationBalanceInfo
        } else {
            text = strings().monetizationBalanceComingLaterInfo
        }
        entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(text, linkHandler: { link in
            arguments.executeLink(link)
        }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    }
    

    if !state.transactions.isEmpty, let transactionsState = state.transactionsState {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
      
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().monetizationTransactionsTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1

        struct Tuple : Equatable {
            let transaction: State.Transaction
            let viewType: GeneralViewType
        }
        var tuples: [Tuple] = []
        for (i, transaction) in state.transactions.enumerated() {
            var viewType = bestGeneralViewTypeAfterFirst(state.transactions, for: i)
            if transactionsState.count > state.transactions.count || transactionsState.isLoadingMore {
                if i == state.transactions.count - 1 {
                    viewType = .innerItem
                }
            }
            tuples.append(.init(transaction: transaction, viewType: viewType))
        }
        
        for (i, tuple) in tuples.enumerated() {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_transaction(i), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
                return TransactionRowItem(initialSize, stableId: stableId, context: arguments.context, transaction: tuple.transaction, viewType: tuple.viewType, action: {
                    arguments.transaction(tuple.transaction)
                })
            }))
        }
        
        if transactionsState.isLoadingMore {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_loading, equatable: nil, comparable: nil, item: { initialSize, stableId in
                return LoadingTableItem(initialSize, height: 40, stableId: stableId, viewType: .lastItem)
            }))
        } else if transactionsState.count > state.transactions.count {
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_load_more, data: .init(name: strings().monetizationTransactionShowMoreTransactionsCountable(Int(transactionsState.count) - state.transactions.count), color: theme.colors.accent, type: .none, viewType: .lastItem, action: arguments.loadMore)))
        }
    }
    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    let premiumConfiguration = PremiumConfiguration.with(appConfiguration: arguments.context.appConfiguration)
    
    let afterNameImage = generateDisclosureActionBoostLevelBadgeImage(text: strings().boostBadgeLevel(Int(premiumConfiguration.minChannelRestrictAdsLevel)))


    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_switch_ad, data: .init(name: strings().monetizationSwitchOffAds, color: theme.colors.text, type: .switchable(state.adsRestricted), viewType: .singleItem, action: arguments.toggleAds, afterNameImage: afterNameImage, autoswitch: false)))
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().monetizationSwitchOffAdsInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1

    
    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

func FragmentMonetizationController(context: AccountContext, peerId: PeerId) -> InputDataController {

    let actionsDisposable = DisposableSet()
    
    let detailedDisposable: DisposableDict<InputDataIdentifier> = DisposableDict()
    actionsDisposable.add(detailedDisposable)
    

    let initialState = State(config_withdraw: context.appConfiguration.getBoolValue("channel_revenue_withdrawal_enabled", orElse: false))
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    class ContextObject {
        let stats: RevenueStatsContext
        let transactions: RevenueStatsTransactionsContext
        init(stats: RevenueStatsContext, transactions: RevenueStatsTransactionsContext) {
            self.stats = stats
            self.transactions = transactions
        }
    }
    
    let stats = RevenueStatsContext(account: context.account, peerId: peerId)
    let transactions = RevenueStatsTransactionsContext(account: context.account, peerId: peerId)
    
    let contextObject = ContextObject(stats: stats, transactions: transactions)
        
    let peer = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
    
    actionsDisposable.add(combineLatest(contextObject.stats.state, contextObject.transactions.state, peer).start(next: { state, transactions, peer in
        if let stats = state.stats {
            updateState { current in
                var current = current
                
                current.peer = peer
                
                current.balance = .init(ton: stats.balances.availableBalance, usdRate: stats.usdRate)
                current.overview.balance = .init(ton: stats.balances.availableBalance, usdRate: stats.usdRate)
                current.overview.all = .init(ton: stats.balances.overallRevenue, usdRate: stats.usdRate)
                current.overview.last = .init(ton: stats.balances.currentBalance, usdRate: stats.usdRate)
                
                current.revenueGraph = stats.revenueGraph
                current.topHoursGraph = stats.topHoursGraph
                                
                var list: [State.Transaction] = []
                
                for transaction in transactions.transactions {
                    switch transaction {
                    case let .withdrawal(status, amount, date, provider, transactionDate, transactionUrl):
                        let mappedStatus: State.Transaction.Status
                        switch status {
                        case .failed:
                            mappedStatus = .failed
                        case .pending:
                            mappedStatus = .pending
                        case .succeed:
                            mappedStatus = .success
                        }
                        list.append(.init(date: date, source: .withdraw(provider: provider, status: mappedStatus, url: transactionUrl), amount: amount))
                    case let .refund(amount, date, provider):
                        list.append(.init(date: date, source: .refund(provider: provider), amount: amount))
                    case let .proceeds(amount, fromDate, toDate):
                        list.append(.init(date: fromDate, source: .incoming(fromDate: fromDate, toDate: toDate), amount: amount))
                    }
                }
                
                current.transactions = list
                current.transactionsState = transactions
                return current
            }
        }
        
        
    }))
    
    actionsDisposable.add(context.engine.peers.checkChannelRevenueWithdrawalAvailability().start(error: { error in
        updateState { current in
            var current = current
            current.withdrawError = error
            return current
        }
    }))
    
    
    let boostStatus = combineLatest(context.engine.peers.getChannelBoostStatus(peerId: peerId), context.engine.peers.getMyBoostStatus(), context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.AdsRestricted(id: peerId)))
    
    actionsDisposable.add(boostStatus.startStandalone(next: { stats, myStatus, adsRestricted in
        updateState { current in
            var current = current
            current.status = stats
            current.myStatus = myStatus
            current.adsRestricted = adsRestricted
            return current
        }
    }))
    
    
    let textInteractions = TextView_Interactions()

    
    textInteractions.processEnter = { event in
        return false
    }
    textInteractions.processAttriburedCopy = { attributedString in
        return globalLinkExecutor.copyAttributedString(attributedString)
    }
    textInteractions.processPaste = { pasteboard in
        if let data = pasteboard.data(forType: .kInApp) {
            let decoder = AdaptedPostboxDecoder()
            if let decoded = try? decoder.decode(ChatTextInputState.self, from: data) {
                let state = decoded.unique(isPremium: true)
                textInteractions.update { _ in
                    return textInteractions.insertText(state.attributedString())
                }
                return true
            }
        }
        return false
    }

    let arguments = Arguments(context: context, interactions: textInteractions, updateState: { state in
        textInteractions.update { _ in
            return state
        }
    }, executeLink: { link in
        execute(inapp: .external(link: link, false))
    }, withdraw: {
        let error = stateValue.with { $0.withdrawError }
        if let error {
            switch error {
            case .authSessionTooFresh, .twoStepAuthTooFresh, .twoStepAuthMissing:
                alert(for: context.window, info: strings().monetizationWithdrawErrorText)
            case .requestPassword:
                showModal(with: InputPasswordController(context: context, title: strings().monetizationWithdrawEnterPasswordTitle, desc: strings().monetizationWithdrawEnterPasswordText, checker: { value in
                    return context.engine.peers.requestChannelRevenueWithdrawalUrl(peerId: peerId, password: value)
                    |> deliverOnMainQueue
                    |> afterNext { url in
                        execute(inapp: .external(link: url, false))
                    } 
                    |> ignoreValues
                    |> mapError { error in
                        switch error {
                        case .invalidPassword:
                            return .wrong
                        case .limitExceeded:
                            return .custom(strings().loginFloodWait)
                        case .generic:
                            return .generic
                        default:
                            return .custom(strings().monetizationWithdrawErrorText)
                        }
                    }
                }), for: context.window)
            default:
                alert(for: context.window, info: strings().unknownError)
            }
        }
    }, promo: {
        showModal(with: FragmentMonetizationPromoController(context: context, peerId: peerId), for: context.window)
    }, loadDetailedGraph: { [weak contextObject] graph, x in
        return contextObject?.stats.loadDetailedGraph(graph, x: x) ?? .complete()
    }, transaction: { transaction in
        let peer: EnginePeer?
        switch transaction.source {
        case .incoming:
            peer = stateValue.with { $0.peer }
        default:
            peer = nil
        }
        showModal(with: FragmentTransactionController(context: context, transaction: transaction, peer: peer), for: context.window)
    }, toggleAds: {
        
        let status = stateValue.with { $0.status }
        let peer = stateValue.with { $0.peer }
        let myBoost = stateValue.with { $0.myStatus }
        let restricted = stateValue.with { $0.adsRestricted }
        
        let needLevel = PremiumConfiguration.with(appConfiguration: context.appConfiguration).minChannelRestrictAdsLevel
        
        if let status, let myBoost, let peer {
            if status.level >= needLevel {
                _ = context.engine.peers.updateChannelRestrictAdMessages(peerId: peerId, restricted: !restricted).startStandalone()
            } else {
                showModal(with: BoostChannelModalController(context: context, peer: peer._asPeer(), boosts: status, myStatus: myBoost, infoOnly: true, source: .noAds(needLevel)), for: context.window)
            }
        }
    }, loadMore: { [weak contextObject] in
        contextObject?.transactions.loadMore()
    }, toggleTransactionType: { mode in
        updateState { current in
            var current = current
            current.transactionMode = mode
            return current
        }
    }, openStarsTransaction: { transaction in
        showModal(with: Star_TransactionScreen(context: context, peer: transaction.peer, transaction: transaction.native), for: context.window)
    })
    
    let signal = statePromise.get() |> deliverOnMainQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments, detailedDisposable: detailedDisposable))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().statsMonetization, hasDone: false)
    
    controller.contextObject = contextObject
    
    
//    controller.didLoad = { [weak contextObject] controller, _ in
//        controller.tableView.setScrollHandler({ position in
//            switch position.direction {
//            case .bottom:
//                contextObject?.transactions.loadMore()
//            default:
//                break
//            }
//        })
//    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    return controller
    
}




private func entries(transaction: State.Transaction, peer: EnginePeer?, context: AccountContext) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("preview"), equatable: .init(transaction), comparable: nil, item: { initialSize, stableId in
        return TransactionPreviewRowItem(initialSize, stableId: stableId, transaction: transaction, peer: peer, context: context, viewType: .singleItem)
    }))
  
    // entries
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

private func FragmentTransactionController(context: AccountContext, transaction: State.Transaction, peer: EnginePeer?) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let controller = InputDataController(dataSignal: .single(InputDataSignalValue(entries: entries(transaction: transaction, peer: peer, context: context))), title: "")
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    let text: String
    switch transaction.source {
    case .incoming:
        text = strings().modalOK
    case .withdraw(_, _, let url):
        if let url = url {
            text = strings().monetizationTransactionInfoViewInExplorer
        } else {
            text = strings().modalOK
        }
    case .refund:
        text = strings().modalOK
    }

    let modalInteractions = ModalInteractions(acceptTitle: text, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true, customTheme: {
        .init(background: theme.colors.background, grayForeground: theme.colors.background, activeBackground: theme.colors.background, listBackground: theme.colors.background)
    })
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    controller.validateData = { [weak modalController] _ in
        switch transaction.source {
        case .withdraw(_, _, let url):
            if let url = url {
                execute(inapp: .external(link: url, false))
            }
        default:
            break
        }
        modalController?.close()
        
        return .none
    }
    
    controller.getBackgroundColor = {
        theme.colors.background
    }
    
//    close = { [weak modalController] in
//        modalController?.modal?.close()
//    }
    
    return modalController
}

