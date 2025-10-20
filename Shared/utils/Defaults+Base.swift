//
//  Defaults+Base.swift
//  XCAChatGPT
//
//  Created by lixindong on 2024/9/28.
//
import Defaults

extension Defaults.Keys {
    static let selectedModelId = Key<String>("selectedModelId", default: "")
    static let maxToken = Key<Int>("maxToken", default: 4096)
    static let selectedProvider = Key<String>("selectedProvider", default: "")
    static let apiKey = Key<String>("apiKey", default: "")
    static let proxyAddress = Key<String>("proxyAddress", default: "")
    static let defaultSource = Key<String>("defaultSource", default: "account")
    static let useAccountCredits = Key<Bool>("useAccountCredits", default: true)
    static let selectedProviderInstanceId = Key<String>("selectedProviderInstanceId", default: "")
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)
    static let conversationOrder = Key<[String]>("conversationOrder", default: [])
    
    // 侧边栏默认收起
    static let collapsed = Key<Bool>("collapsed", default: false)
}
