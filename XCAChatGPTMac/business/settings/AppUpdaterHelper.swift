//
//  AppUpdaterHelper.swift
//  XCAChatGPT
//
//  Created by lixindong on 2024/9/29.
//

import AppUpdater

class AppUpdaterHelper {
    static let shared = AppUpdaterHelper()
    
    let updater = AppUpdater(owner: "Macaify", repo: "MacaifyApp", releasePrefix: "Macaify", proxy: GithubProxy())
    
    func initialize() {
#if !DEBUG
        updater.check()
#endif
    }
}
