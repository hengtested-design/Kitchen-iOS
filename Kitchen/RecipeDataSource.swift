//
//  RecipeDataSource.swift
//  Kitchen
//
//  菜谱数据源 — jsDelivr CDN 远端拉取（主数据源）。
//  Bundled 数据由 RecipeStore 直接读 Bundle JSON, 不再走 protocol 抽象层。
//
//  Created by 灵犀 on 2026/8/7.
//

import Foundation

// MARK: - Errors

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

// MARK: - Remote: jsDelivr CDN（⟳ 按钮拉取）

final class RemoteJSONDataSource: Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.default
        // 提高超时：raw.githubusercontent.com 偶尔慢，30 秒更稳
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = true  // 离线时等网络
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    /// 加载所有菜系清单（先于 loadRecipes 调用）
    func loadCuisines() async throws -> [String] {
        let manifest = try await loadManifest()
        return manifest.cuisines
    }

    /// 加载某菜系下的所有菜
    func loadRecipes(cuisine: String) async throws -> [Recipe] {
        let urlStr = "\(RemoteConfig.cdnBaseURL)/\(cuisine).json"
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

    /// 加载元信息（schema_version / data_version）
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