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
    static let cdnBaseURL = "https://cdn.jsdelivr.net/gh/hengtested-design/Kitchen-Data@main"
    
    /// manifest 文件路径
    static let manifestURL = "\(cdnBaseURL)/manifest.json"
    
    /// HTTP 超时（秒）
    static let requestTimeout: TimeInterval = 8
    
    /// 缓存目录路径
    static let cacheDirectoryName = "RemoteKitchen"
    
    /// 用户在首次启动会拉一次 manifest，之后只在背景刷新
    static let useRemoteData = true
}
