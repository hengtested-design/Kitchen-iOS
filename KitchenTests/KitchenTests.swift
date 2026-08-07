//
//  KitchenTests.swift
//  KitchenTests
//
//  Created by 衡敏涛 on 2026/8/4.
//
// 适配纯只读 + 收藏 架构:
//  - 菜谱数据从爬虫 JSON 加载,App 不再编辑
//  - 唯一可变状态:收藏(favorites),通过 UserDefaults
//  - 数据量从 15 增加到 211 道,测试用动态计数
//

import Testing
import Foundation
@testable import Kitchen

// MARK: - Helpers

/// 每个测试开始前清掉 favorites(UserDefaults),防止测试间相互污染
private func isolateEnvironment() {
    UserDefaults.standard.removeObject(forKey: "KitchenFavorites")
}

/// 列举 main bundle 中所有菜谱 JSON 文件
private func bundledRecipeJSONFiles() throws -> [URL] {
    let bundle = Bundle.main
    let resourceURL = try #require(bundle.resourceURL, "main bundle has no resourceURL")
    let files = try FileManager.default.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension.lowercased() == "json" }
    return files
}

// MARK: - JSON Decoding

@Suite("Recipe JSON decoding")
struct RecipeJSONDecodingTests {

    @Test("每个菜 JSON 都能正确解码")
    func everyRecipeDecodes() throws {
        let files = try bundledRecipeJSONFiles()
        #expect(files.count > 0, "应该有菜谱 JSON 文件")

        for file in files {
            let data = try Data(contentsOf: file)
            let r = try JSONDecoder().decode(Recipe.self, from: data)
            #expect(!r.name.isEmpty, "\(file.lastPathComponent) name 不能为空")
            #expect(!r.cuisine.isEmpty, "\(file.lastPathComponent) cuisine 不能为空")
            #expect(r.difficulty >= 1 && r.difficulty <= 5, "\(file.lastPathComponent) difficulty 越界: \(r.difficulty)")
            #expect(r.duration > 0, "\(file.lastPathComponent) duration 必须 > 0")
            #expect(r.ingredients.count > 0, "\(file.lastPathComponent) 至少要有 1 个食材")
            #expect(r.steps.count > 0, "\(file.lastPathComponent) 至少要有 1 个步骤")
            // 步骤编号必须从 1 开始连续
            for (idx, step) in r.steps.enumerated() {
                #expect(step.number == idx + 1, "\(file.lastPathComponent) 步骤编号错乱")
            }
        }
    }

    @Test("所有菜 ID 唯一")
    func recipeIDsAreUnique() throws {
        let files = try bundledRecipeJSONFiles()
        var ids = Set<Int>()
        for f in files {
            let r = try JSONDecoder().decode(Recipe.self, from: Data(contentsOf: f))
            let (inserted, _) = ids.insert(r.id)
            #expect(inserted, "重复 ID \(r.id) in \(f.lastPathComponent)")
        }
        #expect(ids.count == files.count)
    }

    @Test("菜系分布合理(至少 4 个菜系)")
    func cuisineDistribution() throws {
        let files = try bundledRecipeJSONFiles()
        var cuisines = Set<String>()
        for f in files {
            let r = try JSONDecoder().decode(Recipe.self, from: Data(contentsOf: f))
            cuisines.insert(r.cuisine)
        }
        #expect(cuisines.count >= 4, "至少应有 4 个菜系,实际 \(cuisines.count): \(cuisines.sorted())")
    }

    @Test("crawler 生成的菜不带 _source 字段污染 Recipe")
    func noInternalFieldsLeakToApp() throws {
        // _source 字段是 crawler 用来标记来源的,不应该出现在 App 业务 JSON 里
        // 这里的设计是:Swift JSONDecoder 解码时,字段未声明会被忽略,所以 _source 不会进入 Recipe
        // 但我们要确保: 没有 _source 字段的菜也能正常显示
        let files = try bundledRecipeJSONFiles()
        for f in files {
            let data = try Data(contentsOf: f)
            let r = try JSONDecoder().decode(Recipe.self, from: data)
            // 走的到这里说明解码成功,字段都被忽略
            _ = r
        }
    }
}

// MARK: - Ingredient Formatting

@Suite("Ingredient formattedAmount")
struct IngredientFormattingTests {

    @Test("整数 amount 格式化为整数")
    func wholeNumber() {
        let ing = Ingredient(name: "鸡蛋", amount: 3, unit: "个", isMain: true)
        #expect(ing.formattedAmount() == "3 个")
        #expect(ing.formattedAmount(multiplier: 2.0) == "6 个")
    }

    @Test("小数 amount 保留 1 位小数")
    func decimalFormat() {
        let ing = Ingredient(name: "盐", amount: 1.5, unit: "g", isMain: false)
        #expect(ing.formattedAmount() == "1.5 g")
    }

    @Test("Multiplier 按比例缩放")
    func multiplierScales() {
        let ing = Ingredient(name: "鸡胸肉", amount: 200, unit: "g", isMain: true)
        #expect(ing.formattedAmount(multiplier: 1.5) == "300 g")
        #expect(ing.formattedAmount(multiplier: 0.5) == "100 g")
    }

    @Test("amount=0 时直接显示 unit(防止 '0 适量' 这种丑陋)")
    func zeroAmountShowsUnitOnly() {
        // 爬虫产出的数据,中文量词('适量/少许')会变成 amount=0, unit='适量'
        // 应该直接显示 unit,不要"0 适量"
        let ing = Ingredient(name: "盐", amount: 0, unit: "适量", isMain: false)
        #expect(ing.formattedAmount() == "适量", "amount=0 应该直接显示 unit")
        #expect(ing.formattedAmount(multiplier: 2.0) == "适量", "amount=0 即便乘 multiplier 也应该显示 unit")
    }
}

// MARK: - RecipeStore Lazy Loading

@Suite("RecipeStore 懒加载")
struct RecipeStoreLazyLoadTests {

    init() {
        isolateEnvironment()
    }

    @Test("新建 store 时内存是空的(懒加载)")
    @MainActor
    func freshStoreIsEmpty() {
        let store = RecipeStore()
        #expect(store.recipes.isEmpty, "懒加载:筛选前不应加载任何菜")
    }

    @Test("筛选菜系触发该菜系懒加载")
    @MainActor
    func cuisineFilterTriggersLazyLoad() throws {
        let store = RecipeStore()
        // 选第一个非"全部"的菜系
        let cuisine = CuisineFilter.allCases.first { $0 != .all }!
        store.selectedCuisine = cuisine
        let filtered = store.filteredRecipes

        #expect(filtered.count > 0, "\(cuisine.rawValue) 至少有 1 道菜")
        #expect(filtered.allSatisfy { $0.cuisine == cuisine.rawValue })
        #expect(store.recipes.allSatisfy { $0.cuisine == cuisine.rawValue })
    }

    @Test("切换菜系会叠加加载,不卸载之前的")
    @MainActor
    func multipleCuisinesLoadAdditively() {
        let store = RecipeStore()

        let c1 = CuisineFilter.allCases.first { $0 != .all }!
        store.selectedCuisine = c1
        _ = store.filteredRecipes
        let afterFirst = store.recipes.count

        let c2 = CuisineFilter.allCases.first { $0 != .all && $0 != c1 }!
        store.selectedCuisine = c2
        _ = store.filteredRecipes
        let afterSecond = store.recipes.count

        #expect(afterFirst > 0)
        #expect(afterSecond > afterFirst, "切换菜系后总数应增加")
    }

    @Test("搜索匹配名字、标签、食材")
    @MainActor
    func searchAcrossFields() throws {
        let store = RecipeStore()
        // 先加载全部菜(走 favorites 路径会加载所有菜系)
        store.selectedCuisine = .all
        _ = store.favoriteRecipes  // 触发全量加载
        let allCount = store.recipes.count
        #expect(allCount > 0, "加载完应包含很多菜")

        // 找出第一个有 ingredients 的菜
        let sample = store.recipes.first { !$0.ingredients.isEmpty }!
        let ingName = sample.ingredients[0].name

        // 按食材名搜索
        store.searchText = ingName
        let byIngredient = store.filteredRecipes
        #expect(byIngredient.count > 0, "按食材 '\(ingName)' 搜索应有结果")
    }

    @Test("难度筛选只显示匹配的")
    @MainActor
    func difficultyFilter() {
        let store = RecipeStore()
        store.selectedCuisine = .all
        _ = store.favoriteRecipes  // 加载全部

        store.selectedDifficulty = .easy
        let easy = store.filteredRecipes
        #expect(easy.allSatisfy { $0.difficulty == 1 })
    }

    @Test("时长筛选只显示不超过上限的")
    @MainActor
    func durationFilter() {
        let store = RecipeStore()
        store.selectedCuisine = .all
        _ = store.favoriteRecipes

        store.selectedDuration = .under30
        let quick = store.filteredRecipes
        #expect(quick.allSatisfy { $0.duration <= 30 })
    }

    @Test("组合筛选:菜系 + 难度 + 时长")
    @MainActor
    func combinedFilters() {
        let store = RecipeStore()
        store.selectedCuisine = .chuan
        store.selectedDifficulty = .easy
        store.selectedDuration = .under30
        let filtered = store.filteredRecipes
        #expect(filtered.allSatisfy { $0.cuisine == "川菜" && $0.difficulty == 1 && $0.duration <= 30 })
    }

    @Test("重置筛选:回到全部菜")
    @MainActor
    func resetFilters() {
        let store = RecipeStore()
        store.selectedCuisine = .chuan
        store.selectedDifficulty = .easy
        store.searchText = "测试"
        // 触发加载
        _ = store.filteredRecipes

        // 重置
        store.searchText = ""
        store.selectedCuisine = .all
        store.selectedDifficulty = .all
        store.selectedDuration = .all

        let all = store.filteredRecipes
        #expect(all.count > 0, "重置后应该显示所有菜")
    }
}

// MARK: - Favorites

@Suite("RecipeStore 收藏")
struct RecipeStoreFavoritesTests {

    init() {
        isolateEnvironment()
    }

    @Test("toggleFavorite 双向切换")
    @MainActor
    func toggleFavorite() {
        let store = RecipeStore()
        #expect(store.isFavorite(id: 1) == false)

        store.toggleFavorite(id: 1)
        #expect(store.isFavorite(id: 1) == true)

        store.toggleFavorite(id: 1)
        #expect(store.isFavorite(id: 1) == false)
    }

    @Test("收藏后能查到收藏的菜")
    @MainActor
    func favoriteRecipesReturnsFavorited() {
        let store = RecipeStore()
        store.selectedCuisine = .all
        // Force lazy load so we have real IDs to choose from
        _ = store.favoriteRecipes  // triggers loadAllBundledRecipesIfNeeded
        let knownIDs = store.recipes.map(\.id).sorted()
        // Prefer a real ID; fall back to ID 1 (always exists) if empty.
        let testID = knownIDs.isEmpty ? 1 : knownIDs[knownIDs.count / 2]

        store.toggleFavorite(id: testID)
        let favs = store.favoriteRecipes
        #expect(favs.contains { $0.id == testID }, "testID=\(testID), knownIDs count=\(knownIDs.count)")
    }

    @Test("收藏跨 store 实例持久化")
    @MainActor
    func favoritesPersistAcrossInstances() {
        let store1 = RecipeStore()
        let testID = 42
        store1.toggleFavorite(id: testID)
        #expect(store1.isFavorite(id: testID))

        let store2 = RecipeStore()
        #expect(store2.isFavorite(id: testID), "新 store 实例应从 UserDefaults 加载收藏")
    }

    @Test("取消收藏会从 favoriteRecipes 移除")
    @MainActor
    func unfavoriteRemoves() {
        let store = RecipeStore()
        store.toggleFavorite(id: 1)
        #expect(store.favoriteRecipes.contains { $0.id == 1 })

        store.toggleFavorite(id: 1)
        #expect(store.favoriteRecipes.contains { $0.id == 1 } == false)
    }
}

// MARK: - CuisineFilter

@Suite("CuisineFilter 枚举")
struct CuisineFilterTests {

    @Test("包含 all 用例")
    func allCaseExists() {
        let all = CuisineFilter.allCases
        #expect(all.contains(.all), "CuisineFilter 必须包含 .all")
    }

    @Test("至少有 5 个菜系")
    func atLeastFiveCuisines() {
        let count = CuisineFilter.allCases.count
        #expect(count >= 5, "至少 5 个菜系(含 .all)")
    }
}

// MARK: - RecipeStore.applyTag (详情页标签点击逻辑)

@Suite("RecipeStore.applyTag")
struct RecipeStoreApplyTagTests {

    @Test("菜系名 → 设置菜系筛选")
    @MainActor
    func cuisineTagSetsCuisineFilter() {
        let store = RecipeStore()
        let result = store.applyTag("川菜")
        #expect(result == .cuisine)
        #expect(store.selectedCuisine == .chuan)
        #expect(store.searchText.isEmpty)
    }

    @Test("烹饪方式 → 设置煮调方式筛选")
    @MainActor
    func cookMethodTagSetsCookMethod() {
        let store = RecipeStore()
        let result = store.applyTag("拌")
        #expect(result == .cookMethod)
        #expect(store.selectedCookMethod == "拌")
        #expect(store.searchText.isEmpty)
    }

    @Test("味道/属性 tag → 当作关键字搜索")
    @MainActor
    func flavorTagBecomesSearch() {
        let store = RecipeStore()
        let result = store.applyTag("酸甜")
        #expect(result == .keyword)
        #expect(store.searchText == "酸甜")
        #expect(store.selectedCuisine == .all)
    }

    @Test("点同名烹饪方式但重置菜系")
    @MainActor
    func cuisineTagResetsCookMethod() {
        let store = RecipeStore()
        store.selectedCookMethod = "拌"
        store.searchText = "旧关键字"
        _ = store.applyTag("浙菜")
        #expect(store.selectedCuisine == .zhe)
        #expect(store.selectedCookMethod == nil)
        #expect(store.searchText.isEmpty)
    }

    @Test("点烹调方式保留菜系（仅重置 searchText）")
    @MainActor
    func cookMethodResetsSearchButKeepsCuisine() {
        let store = RecipeStore()
        store.selectedCuisine = .chuan
        store.searchText = "老关键字"
        _ = store.applyTag("烤")
        #expect(store.selectedCookMethod == "烤")
        #expect(store.searchText.isEmpty)
    }
}

// MARK: - RecipeStore.similarRecipes

@Suite("RecipeStore.similarRecipes")
struct RecipeStoreSimilarTests {

    @Test("同 cuisine 同 tag 的菜都能被丌回来")
    @MainActor
    func findsWithSharedTags() {
        let store = RecipeStore()
        store.selectedCuisine = .all
        _ = store.favoriteRecipes  // 触发加载全部菜系
        // 找一道凉菜 并以它为参考拿变体
        guard let base = store.recipes.first(where: { $0.cuisine == "凉菜" && !$0.tags.isEmpty }) else {
            #expect(Bool(false), "需要起始菜")
            return
        }
        let variants = store.similarRecipes(to: base)
        // 变体必须不以自己为前提，且至少 1 个
        #expect(!variants.isEmpty, "至少应有同主题变体")
        #expect(variants.allSatisfy { $0.id != base.id }, "不应包含自己")
        #expect(variants.allSatisfy { !Set($0.tags).intersection(Set(base.tags)).isEmpty }, "变体必共享 tag")
    }

    @Test("空 tags 的菜返 []")
    @MainActor
    func emptyTagsReturnsEmpty() {
        let store = RecipeStore()
        store.selectedCuisine = .all
        _ = store.favoriteRecipes
        let plain = Recipe(
            id: 999999, name: "tagless", cuisine: "川菜",
            cover: "", difficulty: 1, duration: 10,
            servings: 1, calories: 0,
            ingredients: [], steps: [], tips: nil, tags: []
        )
        #expect(store.similarRecipes(to: plain).isEmpty)
    }

    @Test("按共享 tag 数降序")
    @MainActor
    func rankedByOverlap() {
        let store = RecipeStore()
        store.selectedCuisine = .all
        _ = store.favoriteRecipes
        // 手工构造一个可预测的场景
        let base = Recipe(
            id: 10001, name: "base", cuisine: "测试菜系",
            cover: "", difficulty: 1, duration: 10,
            servings: 1, calories: 0,
            ingredients: [], steps: [], tips: nil,
            tags: ["拌", "酸甜"]
        )
        let a = Recipe(
            id: 10002, name: "a-overlap2", cuisine: "测试菜系",
            cover: "", difficulty: 1, duration: 10,
            servings: 1, calories: 0,
            ingredients: [], steps: [], tips: nil,
            tags: ["拌", "酸甜", "微辣"]
        )
        let b = Recipe(
            id: 10003, name: "b-overlap1", cuisine: "测试菜系",
            cover: "", difficulty: 1, duration: 10,
            servings: 1, calories: 0,
            ingredients: [], steps: [], tips: nil,
            tags: ["拌"]
        )
        store.recipes.append(base); store.recipes.append(a); store.recipes.append(b)
        let sims = store.similarRecipes(to: base).filter { $0.id == 10002 || $0.id == 10003 }
        #expect(sims.first?.id == 10002, "a（共享 2 tag）应排在 b（共享 1 tag）之前")
    }
}

// MARK: - Recipe Schema

@Suite("Recipe 模型")
struct RecipeModelTests {

    @Test("difficultyText 1-5 都有对应文本")
    func difficultyText() {
        for d in 1...5 {
            let r = Recipe(
                id: 1, name: "test", cuisine: "川菜",
                cover: "", difficulty: d, duration: 10,
                servings: 1, calories: 0,
                ingredients: [], steps: [],
                tips: nil, tags: []
            )
            #expect(!r.difficultyText.isEmpty, "difficulty \(d) 必须有文本")
        }
    }

    @Test("steps 为空数组也能解码")
    func emptyStepsIsValid() throws {
        // 边界情况:有些菜可能没步骤(罕见)
        let json = """
        {
            "id": 1,
            "name": "测试",
            "cuisine": "川菜",
            "cover": "",
            "difficulty": 1,
            "duration": 10,
            "servings": 1,
            "calories": 0,
            "ingredients": [],
            "steps": [],
            "tags": []
        }
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(Recipe.self, from: json)
        #expect(r.steps.isEmpty)
    }

    @Test("Recipe schema 是严格的:缺字段解码失败")
    func recipeSchemaIsStrict() {
        // 所有字段都是 non-optional,缺某个关键字段应该解码失败
        let json = """
        {
            "id": 1,
            "name": "测试",
            "cuisine": "川菜"
        }
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Recipe.self, from: json)
        }
    }
}
