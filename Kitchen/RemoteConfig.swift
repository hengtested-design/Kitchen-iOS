//
//  RemoteConfig.swift
//  Kitchen
//
//  远程数据源配置。
//  改 baseURL 即可切换不同的数据源（不同 GitHub repo / CDN）。
//
//  Created by 灵犀 on 2026/8/7.
//

import Foundation

enum RemoteConfig {
    /// jsDelivr CDN 提供 GitHub 仓库的全球加速。
    /// 格式：https://cdn.jsdelivr.net/gh/<用户名>/<仓库>@<分支>
    /// 注：分支名改成 commit hash 可永久锁定某个版本
    // 不用 CDN 缓存。改 push 后 ⟳ 立刻能看到。
    // raw.githubusercontent.com。GitHub 原生，无缓存，60 req/hr 不查表。
    // 需要 URL encode 后路径中文能用（现以 %E5%9B%9B 锅肉 这种方式）。
    static let cdnBaseURL = "https://raw.githubusercontent.com/hengtested-design/Kitchen-Data/main"
    
    /// manifest 文件路径
    static let manifestURL = "\(cdnBaseURL)/manifest.json"
    
    /// HTTP 超时（秒）
    static let requestTimeout: TimeInterval = 8
    
    /// 缓存目录路径
    static let cacheDirectoryName = "RemoteKitchen"
    
    /// 用户在首次启动会拉一次 manifest，之后只在背景刷新
    static let useRemoteData = true
}
