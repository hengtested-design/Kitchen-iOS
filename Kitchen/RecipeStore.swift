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

    /// 动态菜系列表 — 预计算缓存，数据变更时更新
    @Published private(set) var availableCuisines: [String] = []
    @Published private(set) var availableMainIngredients: [String] = []
    @Published private(set) var availableCookMethods: [String] = []
    
    private let favoritesKey = "KitchenFavorites"
    
    // Cache: which cuisine bundles have been loaded into memory.
    // Bundled recipe data is read-only (synced via external crawler).
    private var loadedCuisines: Set<String> = []

    // 数据版本,UI 可以用来提示 "数据已更新"
    @Published private(set) var dataSourceDescription: String = "bundled"
    @Published private(set) var lastRefreshedAt: Date?
    /// 后台预加载是否完成。favoriteRecipes 等会读 recipes 的 computed property
    /// 在未完成时返空, 避免 TabView 默认构造所有 Tab body 时同步 load 575 JSON。
    @Published private(set) var isPreloaded: Bool = false
    
    init() {
        loadFavorites()
        // ⚡ 同步读 disk cache (~5ms) — 让 UI 第一帧就拿到菜谱数据，
        // 否则 SwiftUI 首帧看到 recipes.isEmpty  -> 显示 loading 骨架屏,
        // 即使 cache 存在也延迟一帧才出现,违背 '秒显示' 设计目标.
        // 同时验证 cache 有效性: 任何 placeholder 菜 (id==0 或 name=='未命名')
        // 视为脏 cache (旧版本遗留, 之前 fetch-images.py 失败时填入的默认值),
        // 丢弃并重加载,避免 '未命名' 菜出现在首页.
        if let cached = loadDiskCacheSync(), Self.isCacheValid(cached) {
            self.recipes = cached
            for cuisineRaw in Set(cached.map({ $0.cuisine })) {
                self.loadedCuisines.insert(cuisineRaw)
            }
            self.updateDerivedCategories()
            self.isPreloaded = true  // ← 立即标记, 渲染时 favoriteRecipes 不返空
        }
        // 后台 task: verify cache 与 bundled 是否一致, 有差异则刷新 + 重写 cache.
        Task.detached(priority: .utility) { [weak self] in
            await self?.preloadAllBundledInBackground()
        }
    }

    /// 后台一次性预加载所有 bundled — init() 后台启动。
    /// 验证 disk cache 与 bundled 是否一致，不一致时刷新 UI + 重写 cache。
    /// 完成后通过 @Published recipes 触发 UI 重渲。
    private func preloadAllBundledInBackground() async {
        // 在 background actor 里扫描所有 bundled JSON (~150ms)
        let fresh = loadAllBundledRecipesSync()
        
        // 对比 cache 与 fresh 的 id 列表 — id 顺序/集合不一致就刷新
        let cachedIds = Set(recipes.map(\.id))
        let freshIds = Set(fresh.map(\.id))
        
        await MainActor.run {
            // cache miss 场景 (init 没读到 cache): 首次安装, 直接填充
            if !isPreloaded {
                self.recipes = fresh
                for cuisineRaw in Set(fresh.map({ $0.cuisine })) {
                    self.loadedCuisines.insert(cuisineRaw)
                }
                self.updateDerivedCategories()
                self.isPreloaded = true
            }
            // cache 与 bundled 不一致 (app 升级, bundled 新菜): 静默更新
            else if cachedIds != freshIds {
                print("[RecipeStore] 🔄 Cache stale (cached=\(cachedIds.count), fresh=\(freshIds.count)), refreshing...")
                self.recipes = fresh
                for cuisineRaw in Set(fresh.map({ $0.cuisine })) {
                    self.loadedCuisines.insert(cuisineRaw)
                }
                self.updateDerivedCategories()
            }
        }
        
        // 不管是否一致, 都重写 cache (让 cache 文件保持新鲜)
        saveDiskCacheSync(fresh)
    }

    // MARK: - Disk Cache Helpers
    private var cacheFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("all_recipes_cache.json")
    }

    /// 从 Disk Cache 尝试快速加载菜谱 (~5ms)
    private func loadDiskCacheSync() -> [Recipe]? {
        guard let url = cacheFileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        do {
            let recipes = try JSONDecoder().decode([Recipe].self, from: data)
            return recipes.isEmpty ? nil : recipes
        } catch {
            print("[RecipeStore] ⚠️ Disk cache decode error: \(error)")
            return nil
        }
    }

    /// 验证 cache 有效性 — 拒绝含 placeholder 菜的脏 cache
    /// (id==0 / name=='未命名' 都是 Recipe 容错解码的默认值, 表明原始 JSON 损坏)
    private static func isCacheValid(_ cached: [Recipe]) -> Bool {
        if cached.isEmpty { return false }
        let hasPlaceholder = cached.contains { $0.id == 0 || $0.name == "未命名" }
        return !hasPlaceholder
    }

    /// 将菜谱全量列表写入 Disk Cache
    private func saveDiskCacheSync(_ recipes: [Recipe]) {
        guard let url = cacheFileURL, !recipes.isEmpty else { return }
        // 过滤 placeholder 菜 (Recipe 容错解码默认值 — 表明原始 JSON 损坏或缺关键字段)
        // id == 0 是 id 默认值, name == "未命名" / cuisine == "其他" 是 decode fallback
        let valid = recipes.filter { r in
            r.id > 0 && r.name != "未命名" && r.cuisine != "其他"
        }
        do {
            let data = try JSONEncoder().encode(valid)
            try data.write(to: url, options: .atomic)
            print("[RecipeStore] 💾 Saved \(valid.count) recipes to disk cache (filtered \(recipes.count - valid.count) placeholders)")
        } catch {
            print("[RecipeStore] ⚠️ Disk cache save error: \(error)")
        }
    }

    /// 同步加载所有 bundled — 单次遍历 O(N)，不重复扫描目录，不阻塞主线程
    private func loadAllBundledRecipesSync() -> [Recipe] {
        let urls = bundledJSONURLs()
        let decoder = JSONDecoder()
        var loaded: [Recipe] = []
        
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            guard let sep = name.firstIndex(of: "_") else { continue }
            let cuisine = String(name[..<sep])
            loadedCuisines.insert(cuisine)
            
            if let data = try? Data(contentsOf: url) {
                do {
                    let r = try decoder.decode(Recipe.self, from: data)
                    loaded.append(r)
                } catch {
                    print("[RecipeStore] ⚠️ Failed to decode \(url.lastPathComponent): \(error)")
                }
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

    /// 预计算所有衍生分类与标签 (菜系、主料、烹饪工艺)，避免 UI 渲染帧重复索引计算
    func updateDerivedCategories() {
        var cuisineCounts: [String: Int] = [:]
        var mainIngCounts: [String: Int] = [:]
        var cookCounts: [String: Int] = [:]
        let cookKeywords: Set<String> = ["烧", "煮", "炒", "炖", "烤", "炸", "煎", "焖", "拌", "烩", "煨", "腌", "溜", "炝"]

        for r in recipes {
            cuisineCounts[r.cuisine, default: 0] += 1
            for ing in r.ingredients where ing.isMain {
                mainIngCounts[ing.name, default: 0] += 1
            }
            for tag in r.tags where cookKeywords.contains(tag) {
                cookCounts[tag, default: 0] += 1
            }
        }

        self.availableCuisines = cuisineCounts.sorted { $0.value > $1.value }.map { $0.key }
        self.availableMainIngredients = mainIngCounts.sorted { $0.value > $1.value }.prefix(10).map { $0.key }
        self.availableCookMethods = cookCounts.sorted { $0.value > $1.value }.map { $0.key }
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
        // 后台预加载未完成时返空 — 避免 SwiftUI TabView 默认构造收藏 Tab 时
        // 同步主线程 load 575 JSON 造成 600ms 白屏。
        guard isPreloaded else { return [] }
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
        // 后台预加载未完成时返空 — 避免详情页首次点击同步 load 阻塞主线程
        guard isPreloaded else { return [] }
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

                // 过滤 placeholder (mergeRemoteRecipes 内部还会再过滤一次, 这里是 banner 数字)
                let validCount = allLoaded.filter { $0.id > 0 && $0.name != "未命名" && $0.cuisine != "其他" }.count

                await MainActor.run {
                    self.mergeRemoteRecipes(allLoaded, byCuisine: manifest.cuisines)
                    self.dataSourceDescription = "remote-\(manifest.dataVersion)"
                    self.lastRefreshedAt = Date()
                    self.refreshState = .success(
                        at: Date(),
                        dishCount: validCount,
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
    /// - 过滤 placeholder 菜 (id==0 / name=='未命名' / cuisine=='其他') — 这些是 Recipe 容错解码默认值, 表示原数据损坏
    /// - newRecipes 为空时跳过 merge (避免删掉 bundled 却没东西替换)
    private func mergeRemoteRecipes(_ newRecipes: [Recipe], byCuisine cuisines: [String]) {
        let valid = newRecipes.filter { $0.id > 0 && $0.name != "未命名" && $0.cuisine != "其他" }
        guard !valid.isEmpty else {
            print("[RecipeStore] ⚠️ mergeRemoteRecipes: 过滤后无有效菜, 跳过 merge (保护 bundled 数据)")
            return
        }
        for cuisine in cuisines {
            recipes.removeAll { $0.cuisine == cuisine }
            loadedCuisines.insert(cuisine)
        }
        recipes.append(contentsOf: valid)
        // 写入 Disk Cache (saveDiskCacheSync 内部再过滤一次 placeholder, 双重保险)
        saveDiskCacheSync(recipes)
    }
}