//
//  ContentView.swift
//  Kitchen
//
//  Created by 衡敏涛 on 2026/8/4.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: RecipeStore

    var body: some View {
        TabView {
            // MARK: - Tab 1: Explore Recipes
            NavigationStack {
                VStack(spacing: 0) {
                    // Custom Search & Filter Header Bar
                    VStack(spacing: 12) {
                        // Search Bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("搜索菜名、食材或标签...", text: $store.searchText)
                            if !store.searchText.isEmpty {
                                Button {
                                    store.searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.tertiarySystemGroupedBg)
                        .cornerRadius(12)
                        
                        // Cuisine Filter Horizontal Scroll
                        FilterChipRow(
                            items: CuisineFilter.allCases.map { ($0.rawValue, $0 == store.selectedCuisine) },
                            action: { index in
                                store.selectedCuisine = CuisineFilter.allCases[index]
                            }
                        )

                        // Main Ingredient Filter
                        FilterChipRow(
                            items: [("全部", store.selectedMainIngredient == nil)]
                                + store.availableMainIngredients.map { ($0, $0 == store.selectedMainIngredient) },
                            action: { index in
                                if index == 0 {
                                    store.selectedMainIngredient = nil
                                } else {
                                    store.selectedMainIngredient = store.availableMainIngredients[index - 1]
                                }
                            }
                        )

                        // Cook Method Filter
                        FilterChipRow(
                            items: [("全部", store.selectedCookMethod == nil)]
                                + store.availableCookMethods.map { ($0, $0 == store.selectedCookMethod) },
                            action: { index in
                                if index == 0 {
                                    store.selectedCookMethod = nil
                                } else {
                                    store.selectedCookMethod = store.availableCookMethods[index - 1]
                                }
                            }
                        )

                        // Secondary Filters: Difficulty & Duration
                        HStack {
                            // Difficulty Menu
                            Menu {
                                ForEach(DifficultyFilter.allCases) { diff in
                                    Button {
                                        store.selectedDifficulty = diff
                                    } label: {
                                        HStack {
                                            Text(diff.title)
                                            if store.selectedDifficulty == diff {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chart.bar.fill")
                                        .font(.caption)
                                    Text(store.selectedDifficulty == .all ? "难度" : store.selectedDifficulty.title)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(store.selectedDifficulty == .all ? Color.tertiarySystemGroupedBg : Color.orange.opacity(0.15))
                                .foregroundColor(store.selectedDifficulty == .all ? .primary : .orange)
                                .cornerRadius(8)
                            }
                            
                            // Duration Menu
                            Menu {
                                ForEach(DurationFilter.allCases) { dur in
                                    Button {
                                        store.selectedDuration = dur
                                    } label: {
                                        HStack {
                                            Text(dur.title)
                                            if store.selectedDuration == dur {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.fill")
                                        .font(.caption)
                                    Text(store.selectedDuration == .all ? "时长" : store.selectedDuration.title)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(store.selectedDuration == .all ? Color.tertiarySystemGroupedBg : Color.orange.opacity(0.15))
                                .foregroundColor(store.selectedDuration == .all ? .primary : .orange)
                                .cornerRadius(8)
                            }
                            
                            Spacer()
                            
                            // Reset Filters if active
                            if store.hasActiveFilter {
                                Button("重置筛选") {
                                    withAnimation {
                                        store.searchText = ""
                                        store.selectedCuisine = .all
                                        store.selectedDifficulty = .all
                                        store.selectedDuration = .all
                                        store.selectedMainIngredient = nil
                                        store.selectedCookMethod = nil
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                        }
                    }
                    .padding()
                    .background(Color.systemBg)

                    // Recipe Grid List
                    ScrollView {
                        if store.filteredRecipes.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "frying.pan")
                                    .font(.system(size: 60))
                                    .foregroundColor(.secondary)
                                Text("没有找到匹配的菜谱")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("尝试更换筛选条件或搜索关键词")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 80)
                            .frame(maxWidth: .infinity)
                        } else {
                            LazyVStack(spacing: 16) {
                                ForEach(store.filteredRecipes) { recipe in
                                    NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                                        RecipeCardView(recipe: recipe)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding()
                        }
                    }
                    .background(Color.systemGroupedBg)
                }
                .navigationTitle("🍳 家厨 HomeCook")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            CategoryBrowseView()
                        } label: {
                            Image(systemName: "square.grid.3x3.fill")
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .tabItem {
                Label("探索菜谱", systemImage: "fork.knife")
            }

            // MARK: - Tab 2: Favorites
            NavigationStack {
                ScrollView {
                    if store.favoriteRecipes.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "heart.slash")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("暂无收藏的菜谱")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("在菜谱卡片上点击红心添加收藏")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 80)
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(store.favoriteRecipes) { recipe in
                                NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                                    RecipeCardView(recipe: recipe)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                    }
                }
                .background(Color.systemGroupedBg)
                .navigationTitle("❤️ 我的收藏")
            }
            .tabItem {
                Label("我的收藏", systemImage: "heart.fill")
            }
        }
        .accentColor(.orange)
        .task {
            // App 启动后后台拉远端数据，远端成功则覆盖 bundled。
            store.refreshFromRemoteInBackground()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(RecipeStore())
}

// MARK: - FilterChipRow

/// 一行可滚动筛选 chip
struct FilterChipRow: View {
    let items: [(String, Bool)]
    let action: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    let (label, isSelected) = item
                    Button {
                        withAnimation {
                            action(index)
                        }
                    } label: {
                        Text(label)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .bold : .medium)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.orange : Color.secondarySystemGroupedBg)
                            .foregroundColor(isSelected ? .white : .primary)
                            .cornerRadius(20)
                            .shadow(color: isSelected ? Color.orange.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// RecipeStore 预览实例(在 Preview 环境下使用)
extension RecipeStore {
    static var sharedPreview: RecipeStore {
        return RecipeStore()
    }
}
