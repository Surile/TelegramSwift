//
//  PhotoCache.swift
//  Telegram
//
//  Created by keepcoder on 14/03/2017.
//  Copyright © 2017 Telegram. All rights reserved.
//

import Cocoa
import SwiftSignalKitMac
import TelegramCoreMac
import PostboxMac
import TGUIKit

struct PhotoCachedRecord {
    let date:TimeInterval
    let image:CGImage
    let size:Int
    init(image:CGImage, size:Int) {
        self.date = CFAbsoluteTimeGetCurrent()
        self.size = size
        self.image = image
    }
}



enum PhotoCacheKeyEntry : Hashable {
    case avatar(PeerId, TelegramMediaImageRepresentation, NSSize, CGFloat)
    case emptyAvatar(PeerId, String, NSColor, NSSize, CGFloat)
    case media(Media, NSSize, CGFloat, LayoutPositionFlags?)
    case messageId(stableId: Int64, NSSize, CGFloat, LayoutPositionFlags)
    var hashValue:Int {
        switch self {
        case let .avatar(peerId, _, _, _):
            return peerId.id.hashValue
        case let .emptyAvatar(peerId, _, _, _, _):
            return peerId.id.hashValue
        case let .messageId(stableId, _, _, _):
            return stableId.hashValue
        case let .media(media, _, _, _):
            return media.id?.id.hashValue ?? 0
        }
    }
    
    static func ==(lhs:PhotoCacheKeyEntry, rhs: PhotoCacheKeyEntry) -> Bool {
        switch lhs {
        case let .avatar(lhsPeerId, lhsRepresentation, lhsSize, lhsScale):
            if case let .avatar(rhsPeerId, rhsRepresentation, rhsSize, rhsScale) = rhs {
                if lhsPeerId != rhsPeerId {
                    return false
                }
                if lhsSize != rhsSize {
                    return false
                }
                if lhsScale != rhsScale {
                    return false
                }
                if !lhsRepresentation.resource.id.isEqual(to: rhsRepresentation.resource.id)  {
                    return false
                }
                return true
            } else {
                return false
            }
        case let .emptyAvatar(peerId, symbol, color, size, scale):
            if case .emptyAvatar(peerId, symbol, color, size, scale) = rhs {
                return true
            } else {
                return false
            }
        case let .media(lhsMedia, lhsSize, lhsScale, lhsPositionFlags):
            if case let .media(rhsMedia, rhsSize, rhsScale, rhsPositionFlags) = rhs {
                if !lhsMedia.isEqual(rhsMedia) {
                    return false
                }
                if lhsSize != rhsSize {
                    return false
                }
                if lhsPositionFlags != rhsPositionFlags {
                    return false
                }
                if lhsScale != rhsScale {
                    return false
                }
                return true
            } else {
                return false
            }
        case let .messageId(stableId, size, scale, positionFlags):
            if case .messageId(stableId, size, scale, positionFlags) = rhs {
                return true
            } else {
                return false
            }
        }
    }
}



class PhotoCache {
    let memoryLimit:Int
    let maxCount:Int = 1000
    private var values:[PhotoCacheKeyEntry:PhotoCachedRecord] = [:]
    private let queue:Queue = Queue()
    
    init(_ memoryLimit:Int = 16*1024*1024) {
        self.memoryLimit = memoryLimit
    }
    
    func cacheImage(_ image:CGImage, for key:PhotoCacheKeyEntry) {
        queue.justDispatch {
            self.values[key] = PhotoCachedRecord(image: image, size: Int(image.size.width * image.size.height * 4))
            self.freeMemoryIfNeeded()
        }
    }
    
    private func freeMemoryIfNeeded() {
        assert(queue.isCurrent())
        
        let total = values.reduce(0, { (current, value: (key: PhotoCacheKeyEntry, value: PhotoCachedRecord)) -> Int in
            return current + value.value.size
        })
        
        if total > memoryLimit {
            let list = values.map ({($0.key, $0.value)}).sorted(by: { lhs, rhs -> Bool in
                return lhs.1.date < rhs.1.date
            })
            
            var clearedMemorySize: Int = 0
            
            for entry in list {
                values.removeValue(forKey: entry.0)
                clearedMemorySize += entry.1.size
                
                if total - clearedMemorySize < memoryLimit {
                    break
                }
            }
        }
    }
    
    func cachedImage(for key:PhotoCacheKeyEntry) -> CGImage? {
        var image:CGImage? = nil
        queue.sync {
            image = self.values[key]?.image
        }
        return image
    }
    
    func removeRecord(for key:PhotoCacheKeyEntry) {
        queue.justDispatch {
            self.values.removeValue(forKey: key)
        }
    }
    
    func clearAll() {
        queue.justDispatch {
            self.values.removeAll()
        }
    }
}


private let peerPhotoCache = PhotoCache()
private let stickersCache = PhotoCache(32 * 1024 * 1024)


func clearImageCache() -> Signal<Void, Void> {
    return Signal<Void, Void> { subscriber -> Disposable in
        stickersCache.clearAll()
        subscriber.putNext(Void())
        subscriber.putCompletion()
        return EmptyDisposable
    }
}

func cachedPeerPhoto(_ peerId:PeerId, representation: TelegramMediaImageRepresentation, size: NSSize, scale: CGFloat) -> Signal<CGImage?, Void> {
    let entry:PhotoCacheKeyEntry = .avatar(peerId, representation, size, scale)
    return .single(peerPhotoCache.cachedImage(for: entry))
}

func cachePeerPhoto(image:CGImage, peerId:PeerId, representation: TelegramMediaImageRepresentation, size: NSSize, scale: CGFloat) -> Signal <Void, Void> {
    let entry:PhotoCacheKeyEntry = .avatar(peerId, representation, size, scale)
    return .single(peerPhotoCache.cacheImage(image, for: entry))
}

func cachedEmptyPeerPhoto(_ peerId:PeerId, symbol: String, color: NSColor, size: NSSize, scale: CGFloat) -> Signal<CGImage?, Void> {
    let entry:PhotoCacheKeyEntry = .emptyAvatar(peerId, symbol, color, size, scale)
    return .single(peerPhotoCache.cachedImage(for: entry))
}

func cacheEmptyPeerPhoto(image:CGImage, peerId:PeerId, symbol: String, color: NSColor, size: NSSize, scale: CGFloat) -> Signal <Void, Void> {
    let entry:PhotoCacheKeyEntry = .emptyAvatar(peerId, symbol, color, size, scale)
    return .single(peerPhotoCache.cacheImage(image, for: entry))
}


func cachedMedia(media: Media, size: NSSize, scale: CGFloat, positionFlags: LayoutPositionFlags? = nil) -> Signal<CGImage?, Void> {
    let entry:PhotoCacheKeyEntry = .media(media, size, scale, positionFlags)
    return .single(stickersCache.cachedImage(for: entry))
}

func cachedMedia(messageId: Int64, size: NSSize, scale: CGFloat, positionFlags: LayoutPositionFlags? = nil) -> Signal<CGImage?, Void> {
    let entry:PhotoCacheKeyEntry = .messageId(stableId: messageId, size, scale, positionFlags ?? [])
    return .single(stickersCache.cachedImage(for: entry))
}

func cacheMedia(signal:Signal<(CGImage?, Bool), Void>, media: Media, size: NSSize, scale: CGFloat, positionFlags: LayoutPositionFlags? = nil) -> Signal <Void, Void> {
    
    return signal |> filter {$0.1} |> mapToSignal { (image, _) -> Signal<Void, Void> in
        if let image = image {
            let entry:PhotoCacheKeyEntry = .media(media, size, scale, positionFlags)
            return .single(stickersCache.cacheImage(image, for: entry))
        }
        return .complete()
    }
}

func cacheMedia(signal:Signal<(CGImage?, Bool), Void>, messageId: Int64, size: NSSize, scale: CGFloat, positionFlags: LayoutPositionFlags? = nil) -> Signal <Void, Void> {
    
    return signal |> filter {$0.1} |> take(1) |> mapToSignal { (image, _) -> Signal<Void, Void> in
        if let image = image {
            let entry:PhotoCacheKeyEntry = .messageId(stableId: messageId, size, scale, positionFlags ?? [])
            return .single(stickersCache.cacheImage(image, for: entry))
        }
        return .complete()
    }
    
}

