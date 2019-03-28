//
//  MajorBackNavigationBar.swift
//  TelegramMac
//
//  Created by keepcoder on 06/01/2017.
//  Copyright © 2017 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import SwiftSignalKitMac
import TelegramCoreMac
import PostboxMac
class MajorBackNavigationBar: BackNavigationBar {
    private let disposable:MetaDisposable = MetaDisposable()
    private let context:AccountContext
    private let peerId:PeerId
    private let badgeNode:GlobalBadgeNode
    init(_ controller: ViewController, context: AccountContext, excludePeerId:PeerId) {
        self.context = context
        self.peerId = excludePeerId
        badgeNode = GlobalBadgeNode(context.account, sharedContext: context.sharedContext, excludePeerId: excludePeerId, view: View())
        badgeNode.xInset = -22
        super.init(controller)
        
        disposable.set(context.sharedContext.layoutHandler.get().start(next: { [weak self] state in
            if let strongSelf = self {
                switch state {
                case .single:
                    strongSelf.badgeNode.view?.isHidden = false
                default:
                    strongSelf.badgeNode.view?.isHidden = true
                }
            }
        }))
        addSubview(badgeNode.view!)

    }
    
    deinit {
        disposable.dispose()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    
    
}
