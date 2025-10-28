//
//  GithubProxy.swift
//  XCAChatGPT
//
//  Created by lixindong on 2024/9/29.
//


//
//  GithubProxy.swift
//  CleanClip
//
//  Created by lixindong on 2024/7/23.
//  Copyright © 2024 zuimeijia. All rights reserved.
//

import Foundation
import AppUpdater

class GithubProxy: URLRequestProxy {
    let proxyUrl = "https://github-api-proxy.macaify.com?url="
    
    override func apply(to urlString: String) -> String {
        return "\(proxyUrl)\(urlString)"
    }
}
