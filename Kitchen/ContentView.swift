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
                        
                        // Cuisine Filter Horizontal Scroll — 动态菜系 (从实际数据计算)
                        FilterChipRow(
                            items: [("全部", store.selectedCuisineName == nil)]
                                + store.availableCuisines.map { ($0, $0 == store.selectedCuisineName) },
                            action: { index in
                                if index == 0 {
                                    store.selectedCuisineName = nil
                                } else {
                                    store.selectedCuisineName = store.availableCuisines[index - 1]
                                }
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
                                        store.selectedCuisineName = nil
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
                .overlay(alignment: .top) {
                    // 刷新状态浮层 - 状态变化时出现 3 秒后自动隐藏
                    RefreshBanner(state: store.refreshState) {
                        store.dismissRefreshStatus()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        // 手动刷新按钮
                        Button {
                            store.refreshFromRemoteInBackground()
                        } label: {
                            if case .refreshing = store.refreshState {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.orange)
                            }
                        }
                        .disabled({
                            if case .refreshing = store.refreshState { return true }
                            return false
                        }())
                        .accessibilityLabel("刷新菜谱数据")
                    }
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
            // 不自动拉远端：保护 raw.githubusercontent.com 的 60 req/hr 额度。
            // 数据源是 bundled，启动快、不浪费请求。
            // 用户点 ⟳ 才拉。
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

// MARK: - Refresh Banner

/// 刷新状态浮层。状态变化后 3 秒自动隐藏。
struct RefreshBanner: View {
    let state: RecipeStore.RefreshState
    let onDismiss: () -> Void

    var body: some View {
        Group {
            switch state {
            case .refreshing:
                bannerView(icon: "arrow.triangle.2.circlepath", text: "拉取中…", tint: .blue)
            case .success(let date, let count, let version):
                bannerView(icon: "checkmark.circle.fill", text: "已同步 \(count) 道菜 · v\(version)", tint: .green)
            case .failure(let msg):
                bannerView(icon: "exclamationmark.triangle.fill", text: "刷新失败：\(msg)", tint: .red)
            case .idle:
                EmptyView()
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.4), value: state)
    }

    private func bannerView(icon: String, text: String, tint: Color) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(tint)
            Text(text)
                .font(.footnote)
                .foregroundColor(.primary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}
