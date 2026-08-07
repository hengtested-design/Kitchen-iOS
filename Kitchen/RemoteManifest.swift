//
//  RemoteManifest.swift
//  Kitchen
//
//  远程数据源 manifest 模型。
//  对应 https://github.com/<user>/Kitchen-Data/blob/main/manifest.json
//
//  Created by 灵犀 on 2026/8/7.
//

import Foundation

/// GitHub Pages / jsDelivr 上的数据版本清单
struct RemoteManifest: Codable, Sendable {
    let schemaVersion: String      // 协议版本
    let dataVersion: String        // 数据版本号 (e.g. "20260807.1351")
    let updatedAt: String          // ISO 8601
    let total: Int                 // 总菜谱数
    let cuisines: [String]         // 菜系列表
    let files: [String: String]    // 菜系名 -> 文件名
    
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case dataVersion = "data_version"
        case updatedAt = "updated_at"
        case total
        case cuisines
        case files
    }
}
