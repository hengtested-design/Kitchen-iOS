//
//  RecipeStore.swift
//  Kitchen
//
//  Created by 衡敏涛 on 2026/8/4.
//

import Foundation
import Combine
import SwiftUI

@MainActor
class RecipeStore: ObservableObject {
    @Published var recipes: [Recipe] = []
    @Published var favoriteIDs: Set<Int> = []
    
    @Published var searchText: String = ""
    @Published var selectedCuisineName: String? = nil  // nil = "全部"；其他 = 菜系名
    @Published var selectedDifficulty: DifficultyFilter = .all
    @Published var selectedDuration: DurationFilter = .all
    @Published var selectedMainIngredient: String? = nil  // 多面浏览:主料
    @Published var selectedCookMethod: String? = nil       // 多面浏览:烹饪方式

    /// 动态菜系列表 — 从 in-memory recipes 计算, 数据变了自动跟随
    var availableCuisines: [String] {
        var counts: [String: Int] = [:]
        for r in recipes {
            counts[r.cuisine, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map { $0.key }
    }
    
    private let favoritesKey = "KitchenFavorites"
    
    // Cache: which cuisine bundles have been loaded into memory.
    // Bundled recipe data is read-only (synced via external crawler).
    private var loadedCuisines: Set<String> = []
    
    // Data source for bundled JSON (synchronous, tests + offline).
    private let bundledSource = BundledJSONDataSource()
    
    // 数据版本,UI 可以用来提示 "数据已更新"
    @Published private(set) var dataSourceDescription: String = "bundled"
    @Published private(set) var lastRefreshedAt: Date?
    
    init() {
        loadFavorites()
        // 后台预加载所有 bundled — 不阻塞首帧渲染
        // 优化: 之前是“点击时才加载”，但 chip 行的 availableMainIngredients /
        //       availableCookMethods + 收藏 Tab 的 favoriteRecipes 在首帧就会读，
        //       同步加载 575 个 JSON 会造成 600ms 白屏。
        Task.detached(priority: .utility) { [weak self] in
            await self?.preloadAllBundledInBackground()
        }
    }

    /// 后台一次性预加载所有 bundled — 在 init() 后台启动。
    /// 完成后通过 @Published recipes 触发 UI 重渲。
    private func preloadAllBundledInBackground() async {
        // 在 background actor 里同步加载（文件 IO 不需 MainActor）
        let all = loadAllBundledRecipesSync()
        await MainActor.run {
            // 幂等: 如果已经有菜了 (不太可能，但防息) 跳过
            guard self.recipes.isEmpty else { return }
            self.recipes = all
            // 标记所有菜系已加载 — 避免后续 ensureCuisineLoaded 重复 IO
            for cuisineRaw in Set(all.map({ $0.cuisine })) {
                self.loadedCuisines.insert(cuisineRaw)
            }
        }
    }

    /// 同步加载所有 bundled — 只在 background actor 调用, 不阻塞主线程
    private func loadAllBundledRecipesSync() -> [Recipe] {
        var loaded: [Recipe] = []
        // 从 bundle 里扫描出实际存在菜谱的菜系
        for url in bundledJSONURLs() {
            let name = url.deletingPathExtension().lastPathComponent
            // 命名约定: <cuisine>_<slug>.json — 切到第一个 '_'
            guard let sep = name.firstIndex(of: "_") else { continue }
            let cuisine = String(name[..<sep])
            guard !loadedCuisines.contains(cuisine) else { continue }
            loadedCuisines.insert(cuisine)
            loaded.append(contentsOf: loadBundledCuisineSync(cuisine))
        }
        return loaded
    }

    /// 加载某个菜系的 bundled JSON — 同步 IO，仅 background actor 使用
    private func loadBundledCuisineSync(_ cuisineRaw: String) -> [Recipe] {
        let prefix = cuisineRaw + "_"
        var loaded: [Recipe] = []
        for url in bundledJSONURLs() {
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix(prefix) else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                let r = try JSONDecoder().decode(Recipe.self, from: data)
                loaded.append(r)
            } catch {
                print("[RecipeStore] ⚠️ Failed to decode \(url.lastPathComponent): \(error)")
            }
        }
        return loaded
    }
    
    // MARK: - Derived Data
    var filteredRecipes: [Recipe] {
        // Pre-load bundles BEFORE filtering. Modifying `recipes` inside the
        // filter closure would mutate a snapshot Swift already iterated past.
        if let cuisine = selectedCuisineName {
            ensureCuisineLoaded(cuisine)
        }
        if !searchText.isEmpty {
            // Searching may match bundled recipes from any cuisine — load them
            // all so search results are complete.
            loadAllBundledRecipesIfNeeded()
        }
        
        return recipes.filter { recipe in
            let matchesSearch: Bool
            if searchText.isEmpty {
                matchesSearch = true
            } else {
                let query = searchText.lowercased()
                let matchName = recipe.name.lowercased().contains(query)
                let matchTag = recipe.tags.contains { $0.lowercased().contains(query) }
                let matchIngredient = recipe.ingredients.contains { $0.name.lowercased().contains(query) }
                matchesSearch = matchName || matchTag || matchIngredient
            }
            
            let matchesCuisine = (selectedCuisineName == nil) || (recipe.cuisine == selectedCuisineName)
            let matchesDifficulty = (selectedDifficulty == .all) || (recipe.difficulty == selectedDifficulty.rawValue)
            let matchesDuration = (selectedDuration == .all) || (recipe.duration <= selectedDuration.rawValue)
            let matchesIngredient = selectedMainIngredient == nil
                || recipe.ingredients.contains { $0.isMain && $0.name == selectedMainIngredient }
            let matchesMethod = selectedCookMethod == nil
                || recipe.tags.contains { $0 == selectedCookMethod }

            return matchesSearch && matchesCuisine && matchesDifficulty && matchesDuration
                && matchesIngredient && matchesMethod
        }
    }

    // 多面浏览:提取当前已加载菜中的高频主料(前 10)
    var availableMainIngredients: [String] {
        var counts: [String: Int] = [:]
        for r in recipes {
            for ing in r.ingredients where ing.isMain {
                counts[ing.name, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
    }

    // 多面浏览:提取烹饪方式(从 tags 里的工艺词)
    var availableCookMethods: [String] {
        let cookKeywords: Set<String> = ["烧", "煮", "炒", "炖", "烤", "炸", "煎", "焖", "拌", "烩", "煨", "腌", "溜", "炝"]
        var counts: [String: Int] = [:]
        for r in recipes {
            for tag in r.tags where cookKeywords.contains(tag) {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }
            .map { $0.key }
    }

    // 菜单使用:在某个菜系下,主料选中的重置
    var hasActiveFilter: Bool {
        selectedCuisineName != nil
        || selectedDifficulty != .all
        || selectedDuration != .all
        || selectedMainIngredient != nil
        || selectedCookMethod != nil
        || !searchText.isEmpty
    }
    
    var favoriteRecipes: [Recipe] {
        // Make sure all bundled data is loaded so favorited items remain visible.
        loadAllBundledRecipesIfNeeded()
        return recipes.filter { favoriteIDs.contains($0.id) }
    }
    
    // MARK: - Favorites
    func isFavorite(id: Int) -> Bool {
        favoriteIDs.contains(id)
    }
    
    func toggleFavorite(id: Int) {
        if favoriteIDs.contains(id) {
            favoriteIDs.remove(id)
        } else {
            favoriteIDs.insert(id)
        }
        saveFavorites()
    }
    
    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteIDs), forKey: favoritesKey)
    }
    
    private func loadFavorites() {
        if let saved = UserDefaults.standard.array(forKey: favoritesKey) as? [Int] {
            favoriteIDs = Set(saved)
        }
    }

    // MARK: - 相似菜谱（口味变体）
    /// 返回与所给菜谱“类似”的其他菜谱：共享至少 1 个 tag 的不同菜，按 tag 重合数降序。
    /// 可能跨菜系，为避免缺失加载，内部会按需加载所有菜系。
    func similarRecipes(to recipe: Recipe, limit: Int = 10) -> [Recipe] {
        if recipe.tags.isEmpty { return [] }
        // 确保变体能从内存里读到
        loadAllBundledRecipesIfNeeded()
        let myTags = Set(recipe.tags)
        return recipes
            .filter { $0.id != recipe.id }
            .map { ($0, Set($0.tags).intersection(myTags).count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    // MARK: - Tag → Filter 跳转逻辑（给 RecipeDetailView 用）

    /// 8 个烹饪方式关键词，用于判别某个 tag 是“烹饪工艺”还是“味道/属性”
    static let cookKeywords: Set<String> = [
        "烧", "煮", "炒", "炖", "烤", "炸", "煎", "焖", "拌", "烩",
        "煨", "腌", "溜", "炝"
    ]

    /// 点击菜谱详情页上的某个 tag / 菜系药丸时的跳转策略。
    /// 返回该 tag 被归类为哪一类（用于 UI 调试）。
    @discardableResult
    func applyTag(_ tag: String) -> FilterType {
        // 菜系名称 → 设置菜系筛选（根据动态菜系表匹配, 而不是写死 enum）
        if availableCuisines.contains(tag) {
            selectedCuisineName = tag
            searchText = ""
            selectedMainIngredient = nil
            selectedCookMethod = nil
            return .cuisine
        }
        // 烹饪方式 → 设置烹饪方式筛选
        if Self.cookKeywords.contains(tag) {
            selectedCookMethod = tag
            searchText = ""
            return .cookMethod
        }
        // 其他（味道/属性，如 "酸甜"/"麻辣") → 关键字搜索
        selectedCuisineName = nil
        searchText = tag
        return .keyword
    }

    enum FilterType {
        case cuisine
        case cookMethod
        case keyword
    }
    
    // MARK: - Lazy Bundled Recipe Loading
    /// Load every bundled cuisine (used when showing favorites so all favorited
    /// recipes remain visible).
    private func loadAllBundledRecipesIfNeeded() {
        // 从 bundle 文件名推断所有菜系 — 不依赖写死的 enum
        for url in bundledJSONURLs() {
            let name = url.deletingPathExtension().lastPathComponent
            if let sep = name.firstIndex(of: "_") {
                let cuisine = String(name[..<sep])
                ensureCuisineLoaded(cuisine)
            }
        }
    }
    
    /// Load one cuisine's bundled JSON files if not already loaded.
    /// Triggered automatically when the user filters by a specific cuisine.
    /// Files are named `<cuisine>_<slug>.json` so Xcode's flat-resource bundling
    /// still works without preserving subdirectory structure.
    private func ensureCuisineLoaded(_ cuisineRaw: String) {
        guard !loadedCuisines.contains(cuisineRaw) else { return }
        loadedCuisines.insert(cuisineRaw)
        
        let prefix = cuisineRaw + "_"
        var loaded: [Recipe] = []
        
        for url in bundledJSONURLs() {
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix(prefix) else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                let r = try JSONDecoder().decode(Recipe.self, from: data)
                loaded.append(r)
            } catch {
                print("[RecipeStore] ⚠️ Failed to decode \(url.lastPathComponent): \(error)")
            }
        }
        
        recipes.append(contentsOf: loaded)
    }
    
    /// Enumerate all .json files in the main bundle's resource directory.
    private func bundledJSONURLs() -> [URL] {
        // 测试运行时 Bundle.main 是 test bundle (xctest), 拿不到 Kitchen.app 的菜谱 JSON。
        // 用 Bundle(for: RecipeStore.self) 直接拿到 Kitchen.app bundle, 保证测试/生产一致。
        let bundle = Bundle(for: RecipeStore.self)
        guard let bundleURL = bundle.resourceURL else { return [] }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.pathExtension.lowercased() == "json" }
    }

    // MARK: - Remote Refresh (opt-in)

    /// 刷新状态枚举，UI 侧用来显示反馈。
    enum RefreshState: Equatable {
        case idle
        case refreshing
        case success(at: Date, dishCount: Int, manifestVersion: String)
        case failure(message: String)
    }

    @Published private(set) var refreshState: RefreshState = .idle

    /// 从远程数据源后台拉取,覆盖已加载的菜系的数据。
    /// 由 ContentView 的 .task modifier 或手动 ⟳ 按钮调用。
    /// 失败不致命,失败时保留 bundled 数据。
    func refreshFromRemoteInBackground() {
        guard RemoteConfig.useRemoteData else {
            refreshState = .failure(message: "remote data disabled")
            return
        }

        // 防止重复点击
        if refreshState == .refreshing { return }
        refreshState = .refreshing

        let source = RemoteJSONDataSource()

        Task { [weak self] in
            guard let self else { return }

            do {
                let manifest = try await source.loadManifest()
                print("[RecipeStore] 📥 remote manifest: \(manifest.total) 道菜 / \(manifest.dataVersion)")

                var allLoaded: [Recipe] = []
                for cuisine in manifest.cuisines {
                    do {
                        let recipes = try await source.loadRecipes(cuisine: cuisine)
                        allLoaded.append(contentsOf: recipes)
                    } catch {
                        print("[RecipeStore] ⚠️ remote load \(cuisine) failed: \(error)")
                    }
                }

                await MainActor.run {
                    self.mergeRemoteRecipes(allLoaded, byCuisine: manifest.cuisines)
                    self.dataSourceDescription = "remote-\(manifest.dataVersion)"
                    self.lastRefreshedAt = Date()
                    self.refreshState = .success(
                        at: Date(),
                        dishCount: allLoaded.count,
                        manifestVersion: manifest.dataVersion
                    )
                    // 3 秒后回到 idle (让 UI 能显示 状态)
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run {
                            if case .success = self.refreshState {
                                self.refreshState = .idle
                            }
                        }
                    }
                }
            } catch {
                print("[RecipeStore] ⚠️ remote manifest failed (使用 bundled 兑底): \(error)")
                await MainActor.run {
                    self.refreshState = .failure(message: "\(error)".prefix(80).description)
                }
            }
        }
    }

    /// 复位刷新状态，供 UI 重置使用
    func dismissRefreshStatus() {
        refreshState = .idle
    }

    /// 用远程数据替换相同菜系的 bundled 数据。
    private func mergeRemoteRecipes(_ newRecipes: [Recipe], byCuisine cuisines: [String]) {
        for cuisine in cuisines {
            recipes.removeAll { $0.cuisine == cuisine }
            loadedCuisines.insert(cuisine)
        }
        recipes.append(contentsOf: newRecipes)
    }
}