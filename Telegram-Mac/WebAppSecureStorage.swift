//
//  WebAppSecureStorage.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 25.03.2025.
//  Copyright © 2025 Telegram. All rights reserved.
//


import Foundation
import Security
import SwiftSignalKit
import TelegramCore

final class WebAppSecureStorage {
    enum Error {
        case quotaExceeded
        case unknown
    }
    
    static private let maxKeyCount = 10
    
    private init() {
    }
    
    static private func keyPrefix(context: AccountContext, botId: EnginePeer.Id) -> String {
        return "WebBot\(UInt64(bitPattern: botId.toInt64()))A\(UInt64(bitPattern: context.account.peerId.toInt64()))Key_"
    }
    
    static private func makeQuery(context: AccountContext, botId: EnginePeer.Id, key: String) -> [String: Any] {
        let identifier = self.keyPrefix(context: context, botId: botId) + key
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecAttrService as String: "TMASecureStorage"
        ]
    }
    
    static private func countKeys(context: AccountContext, botId: EnginePeer.Id) -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "TMASecureStorage",
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let items = result as? [[String: Any]] {
            let relevantPrefix = self.keyPrefix(context: context, botId: botId)
            let count = items.filter {
                if let account = $0[kSecAttrAccount as String] as? String {
                    return account.hasPrefix(relevantPrefix)
                }
                return false
            }.count
            return count
        }
        
        return 0
    }
    
    static func setValue(context: AccountContext, botId: EnginePeer.Id, key: String, value: String?) -> Signal<Never, WebAppSecureStorage.Error> {
        var query = makeQuery(context: context, botId: botId, key: key)
        if value == nil {
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecSuccess || status == errSecItemNotFound {
                return .complete()
            } else {
                return .fail(.unknown)
            }
        }
        
        guard let valueData = value?.data(using: .utf8) else {
            return .fail(.unknown)
        }
        
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
            
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let updateQuery: [String: Any] = [
                kSecValueData as String: valueData
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, updateQuery as CFDictionary)
            if updateStatus == errSecSuccess {
                return .complete()
            } else {
                return .fail(.unknown)
            }
        } else if status == errSecItemNotFound {
            let currentCount = countKeys(context: context, botId: botId)
            if currentCount >= maxKeyCount {
                return .fail(.quotaExceeded)
            }
            
            query[kSecValueData as String] = valueData
            
            let createStatus = SecItemAdd(query as CFDictionary, nil)
            if createStatus == errSecSuccess {
                return .complete()
            } else {
                return .fail(.unknown)
            }
        } else {
            return .fail(.unknown)
        }
    }
    
    static func getValue(context: AccountContext, botId: EnginePeer.Id, key: String) -> Signal<String?, WebAppSecureStorage.Error> {
        var query = makeQuery(context: context, botId: botId, key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) {
            return .single(value)
        } else if status == errSecItemNotFound {
            return .single(nil)
        } else {
            return .fail(.unknown)
        }
    }
    
    static func clearStorage(context: AccountContext, botId: EnginePeer.Id) -> Signal<Never, WebAppSecureStorage.Error> {
        let serviceQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "TMASecureStorage",
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(serviceQuery as CFDictionary, &result)
        
        if status == errSecSuccess, let items = result as? [[String: Any]] {
            let relevantPrefix = self.keyPrefix(context: context, botId: botId)
            
            for item in items {
                if let account = item[kSecAttrAccount as String] as? String, account.hasPrefix(relevantPrefix) {
                    let deleteQuery: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrAccount as String: account,
                        kSecAttrService as String: "TMASecureStorage"
                    ]
                    
                    SecItemDelete(deleteQuery as CFDictionary)
                }
            }
        }
        return .complete()
    }
}

