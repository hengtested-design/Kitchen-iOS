//
//  RecipeDataSource.swift
//  Kitchen
//
//  抽象菜谱数据源协议 + 两个实现：
//    - BundledJSONDataSource: 从 app bundle 读 JSON（兜底/种子）
//    - RemoteJSONDataSource:  从 jsDelivr CDN 拉 JSON（主数据源）
//
//  Created by 灵犀 on 2026/8/7.
//

import Foundation

// MARK: - Protocol

/// 菜谱数据源抽象。
/// RecipeStore 通过它读菜谱列表，不关心数据具体在本地还是远程。
protocol RecipeDataSource: Sendable {
    /// 加载所有菜系清单（先于 loadRecipes 调用）
    func loadCuisines() async throws -> [String]
    
    /// 加载某菜系下的所有菜
    func loadRecipes(cuisine: String) async throws -> [Recipe]
    
    /// 加载元信息（schema_version / data_version）
    func loadManifest() async throws -> RemoteManifest
}

enum RecipeDataSourceError: LocalizedError {
    case invalidResponse
    case decodingFailed(String)
    case fileNotFound(String)
    case httpError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .decodingFailed(let s): return "Decoding failed: \(s)"
        case .fileNotFound(let s): return "File not found: \(s)"
        case .httpError(let code): return "HTTP error: \(code)"
        }
    }
}


// MARK: - Bundled: app 内置 JSON（兜底 / 种子数据）

final class BundledJSONDataSource: RecipeDataSource {
    private let bundle: Bundle
    
    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }
    
    func loadCuisines() async throws -> [String] {
        let urls = try bundledJSONURLs()
        var cuisines = Set<String>()
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            // 文件命名约定：<cuisine>_<slug>.json
            // 切到第一个 '_' 取菜系
            if let separator = name.firstIndex(of: "_") {
                let cuisine = String(name[..<separator])
                cuisines.insert(cuisine)
            }
        }
        return cuisines.sorted()
    }
    
    func loadRecipes(cuisine: String) async throws -> [Recipe] {
        let prefix = cuisine + "_"
        let decoder = JSONDecoder()
        var recipes: [Recipe] = []
        for url in try bundledJSONURLs() {
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix(prefix) else { continue }
            do {
                let data = try Data(contentsOf: url)
                let recipe = try decoder.decode(Recipe.self, from: data)
                recipes.append(recipe)
            } catch {
                print("[Bundled] ⚠️ Failed to decode \(url.lastPathComponent): \(error)")
            }
        }
        return recipes
    }
    
    func loadManifest() async throws -> RemoteManifest {
        // Bundle 中的菜谱没有 manifest 文件，构造一份"永久版"
        let urls = try bundledJSONURLs()
        let total = urls.count
        var cuisines = Set<String>()
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            if let sep = name.firstIndex(of: "_") {
                cuisines.insert(String(name[..<sep]))
            }
        }
        return RemoteManifest(
            schemaVersion: "1.0",
            dataVersion: "bundled-\(total)",
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            total: total,
            cuisines: cuisines.sorted(),
            files: [:]
        )
    }
    
    private func bundledJSONURLs() throws -> [URL] {
        guard let bundleURL = bundle.resourceURL else { return [] }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.pathExtension.lowercased() == "json" }
    }
}


// MARK: - Remote: jsDelivr CDN（主数据源）

final class RemoteJSONDataSource: RecipeDataSource {
    private let session: URLSession
    private let decoder: JSONDecoder
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = RemoteConfig.requestTimeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }
    
    func loadCuisines() async throws -> [String] {
        let manifest = try await loadManifest()
        return manifest.cuisines
    }
    
    func loadRecipes(cuisine: String) async throws -> [Recipe] {
        let manifest = try await loadManifest()
        guard let fileName = manifest.files[cuisine] else {
            throw RecipeDataSourceError.fileNotFound(cuisine)
        }
        let urlStr = "\(RemoteConfig.cdnBaseURL)/\(fileName)"
        guard let url = URL(string: urlStr) else {
            throw RecipeDataSourceError.fileNotFound(urlStr)
        }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RecipeDataSourceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw RecipeDataSourceError.httpError(http.statusCode)
        }
        
        do {
            return try decoder.decode([Recipe].self, from: data)
        } catch {
            throw RecipeDataSourceError.decodingFailed("\(cuisine): \(error)")
        }
    }
    
    func loadManifest() async throws -> RemoteManifest {
        guard let url = URL(string: RemoteConfig.manifestURL) else {
            throw RecipeDataSourceError.invalidResponse
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw RecipeDataSourceError.invalidResponse
        }
        do {
            return try decoder.decode(RemoteManifest.self, from: data)
        } catch {
            throw RecipeDataSourceError.decodingFailed("manifest: \(error)")
        }
    }
}
