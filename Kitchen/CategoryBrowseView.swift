//
//  CategoryBrowseView.swift
//  Kitchen
//
//  分面浏览入口:按主料 / 按烹饪方式 / 按口味分组
//  选中一个分类后,返回首页并自动应用筛选
//

import SwiftUI

struct CategoryBrowseView: View {
    @EnvironmentObject var store: RecipeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // MARK: - 按主料
            Section {
                Button {
                    store.selectedMainIngredient = nil
                    store.selectedCookMethod = nil
                    store.selectedCuisineName = nil
                } label: {
                    HStack {
                        Image(systemName: "rectangle.grid.2x2.fill")
                            .foregroundColor(.orange)
                        Text("全部 / 不筛选")
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(store.recipes.count) 道")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                ForEach(store.availableMainIngredients, id: \.self) { ing in
                    Button {
                        applyFilter(ingredient: ing)
                    } label: {
                        HStack {
                            Image(systemName: "leaf.fill")
                                .foregroundColor(.green)
                            Text(ing)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(countByIngredient(ing)) 道")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("🥬 按主料")
            }

            // MARK: - 按烹饪方式
            Section {
                ForEach(store.availableCookMethods, id: \.self) { method in
                    Button {
                        applyFilter(cookMethod: method)
                    } label: {
                        HStack {
                            Image(systemName: iconForMethod(method))
                                .foregroundColor(.orange)
                            Text(methodNameFor(method))
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(countByMethod(method)) 道")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("🔥 按烹饪方式")
            }

            // MARK: - 按口味
            Section {
                ForEach(availableTasteTags(), id: \.self) { taste in
                    Button {
                        applyFilter(taste: taste)
                    } label: {
                        HStack {
                            Image(systemName: iconForTaste(taste))
                                .foregroundColor(.purple)
                            Text(taste)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(countByTaste(taste)) 道")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("🌶️ 按口味")
            }
        }
        .navigationTitle("📚 分类浏览")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 确保所有菜都已加载,以便统计
            _ = store.favoriteRecipes
        }
    }

    // MARK: - 应用筛选并返回

    private func applyFilter(ingredient: String? = nil, cookMethod: String? = nil, taste: String? = nil) {
        store.selectedMainIngredient = ingredient
        store.selectedCookMethod = cookMethod
        store.selectedCuisineName = nil
        store.selectedDifficulty = .all
        store.selectedDuration = .all
        store.searchText = ""
        // 设定后掉一下页面,回首页看筛选后的菜
        dismiss()
    }

    private func applyFilter(ingredient: String) {
        applyFilter(ingredient: ingredient, cookMethod: nil, taste: nil)
    }

    private func applyFilter(cookMethod: String) {
        applyFilter(ingredient: nil, cookMethod: cookMethod, taste: nil)
    }

    private func applyFilter(taste: String) {
        // 口味不在 tags 里走,而是直接 search
        store.searchText = taste
        store.selectedMainIngredient = nil
        store.selectedCookMethod = nil
        store.selectedCuisineName = nil
        store.selectedDifficulty = .all
        store.selectedDuration = .all
        dismiss()
    }

    // MARK: - 统计

    private func countByIngredient(_ name: String) -> Int {
        store.recipes.filter { $0.ingredients.contains { $0.isMain && $0.name == name } }.count
    }

    private func countByMethod(_ method: String) -> Int {
        store.recipes.filter { $0.tags.contains(method) }.count
    }

    private func countByTaste(_ taste: String) -> Int {
        store.recipes.filter { $0.tags.contains(taste) }.count
    }

    /// 已知口味标签(从数据里看哪些出现最多)
    private func availableTasteTags() -> [String] {
        let tastes: Set<String> = [
            "麻辣", "咸鲜", "咸甜", "酸甜", "微辣", "鱼香", "原味", "酸辣", "甜味", "葱香", "酸咸", "中辣", "超辣"
        ]
        var counts: [String: Int] = [:]
        for r in store.recipes {
            for tag in r.tags where tastes.contains(tag) {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map { $0.key }
    }

    // MARK: - 显示辅助

    private func iconForMethod(_ method: String) -> String {
        switch method {
        case "烧": return "flame.fill"
        case "煮": return "drop.fill"
        case "炒": return "frying.pan.fill"
        case "炖": return "pot.fill"
        case "烤": return "oven.fill"
        case "炸": return "burst.fill"
        case "煎": return "rectangle.fill"
        case "蒸": return "cloud.fill"
        case "凉拌", "拌": return "leaf.fill"
        default: return "frying.pan"
        }
    }

    private func methodNameFor(_ method: String) -> String {
        switch method {
        case "烧": return "烧 / 红烧"
        case "煮": return "煮 / 汤"
        case "炒": return "炒"
        case "炖": return "炖 / 慢炖"
        case "烤": return "烤"
        case "炸": return "炸"
        case "煎": return "煎"
        case "蒸": return "蒸"
        case "凉拌", "拌": return "凉拌"
        case "焖": return "焖"
        default: return method
        }
    }

    private func iconForTaste(_ taste: String) -> String {
        if taste.contains("辣") || taste.contains("麻辣") { return "flame.fill" }
        if taste.contains("甜") { return "heart.fill" }
        if taste.contains("酸") { return "drop.triangle.fill" }
        if taste.contains("咸") { return "circle.fill" }
        return "sparkles"
    }
}

#Preview {
    NavigationStack {
        CategoryBrowseView()
            .environmentObject(RecipeStore())
    }
}
