//
//  RecipeDetailView.swift
//  Kitchen
//
//  Created by 衡敏涛 on 2026/8/4.
//

import SwiftUI

struct RecipeDetailView: View {
    let recipe: Recipe
    @EnvironmentObject var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    
    // Interactive Serving Multiplier State
    @State private var currentServings: Int
    // Interactive Completed Steps Tracking
    @State private var completedSteps: Set<Int> = []
    
    init(recipe: Recipe) {
        self.recipe = recipe
        _currentServings = State(initialValue: recipe.servings)
    }
    
    var servingMultiplier: Double {
        Double(currentServings) / Double(max(recipe.servings, 1))
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
                // Hero Header Image
                ZStack(alignment: .bottomLeading) {
                    heroImage
                    .frame(height: 250)
                    .clipped()
                    
                    // Gradient overlay
                    LinearGradient(
                        colors: [.black.opacity(0.6), .clear],
                        startPoint: .bottom,
                        endPoint: .center
                    )
                    .frame(height: 250)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        // 变体选择切到下方 carousel，页顶不再放装饰药丸
                        Text(recipe.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding()
                }
                
                // Key Metrics Bar
                HStack(spacing: 0) {
                    MetricItem(icon: "clock.fill", title: "烹饪时间", value: "\(recipe.duration)分钟", color: .blue)
                    Divider().frame(height: 30)
                    MetricItem(icon: "chart.bar.fill", title: "难易程度", value: recipe.difficultyText, color: difficultyColor(for: recipe.difficulty))
                    if recipe.calories > 0 {
                        Divider().frame(height: 30)
                        MetricItem(icon: "flame.fill", title: "热量卡路里", value: "\(recipe.calories)千卡", color: .orange)
                    }
                }
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondarySystemGroupedBg))
                .padding(.horizontal)
                
                // Servings Scaler Control
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("🍽️ 份量调节")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text("根据就餐人数动态计算配料用量")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Button {
                            if currentServings > 1 {
                                currentServings -= 1
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(currentServings > 1 ? .orange : .gray.opacity(0.4))
                        }
                        
                        Text("\(currentServings) 人份")
                            .font(.title3)
                            .fontWeight(.bold)
                            .frame(minWidth: 60)
                        
                        Button {
                            currentServings += 1
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.orange.opacity(0.1)))
                }
                .padding(.horizontal)
                
                // Ingredients Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("🥕 配料表")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    // Main Ingredients
                    let mainIngredients = recipe.ingredients.filter { $0.isMain }
                    if !mainIngredients.isEmpty {
                        Text("主料")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(mainIngredients) { ing in
                                IngredientBadge(ingredient: ing, multiplier: servingMultiplier, isMain: true)
                            }
                        }
                    }
                    
                    // Sub Ingredients / Seasonings
                    let subIngredients = recipe.ingredients.filter { !$0.isMain }
                    if !subIngredients.isEmpty {
                        Text("辅料与调料")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(subIngredients) { ing in
                                IngredientBadge(ingredient: ing, multiplier: servingMultiplier, isMain: false)
                            }
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.secondarySystemGroupedBg))
                .padding(.horizontal)
                
                // Cooking Steps Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("👨‍🍳 烹饪步骤")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        Text("\(completedSteps.count)/\(recipe.steps.count) 完成")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                    
                    ForEach(recipe.steps) { step in
                        let isDone = completedSteps.contains(step.number)
                        HStack(alignment: .top, spacing: 14) {
                            // Number Badge / Checkbox
                            Button {
                                withAnimation {
                                    if isDone {
                                        completedSteps.remove(step.number)
                                    } else {
                                        completedSteps.insert(step.number)
                                    }
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(isDone ? Color.green : Color.orange)
                                        .frame(width: 32, height: 32)
                                    
                                    if isDone {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundColor(.white)
                                    } else {
                                        Text("\(step.number)")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(step.description)
                                    .font(.body)
                                    .foregroundColor(isDone ? .secondary : .primary)
                                    .strikethrough(isDone)
                                
                                if let tips = step.tips, !tips.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "lightbulb.fill")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                        Text(tips)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(6)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                                }
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(isDone ? Color.green.opacity(0.06) : Color.tertiarySystemGroupedBg))
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.secondarySystemGroupedBg))
                .padding(.horizontal)
                
                // General Chef's Tips
                if let tips = recipe.tips, !tips.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.orange)
                            Text("大厨小贴士")
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        Text(tips)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.orange.opacity(0.12)))
                    .padding(.horizontal)
                }

                // MARK: - 口味变体 - 同主题其他做法
                let variants = store.similarRecipes(to: recipe)
                if !variants.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "square.grid.2x2")
                                .foregroundColor(.purple)
                            Text("口味变体")
                                .font(.headline)
                                .fontWeight(.bold)
                            Spacer()
                            Text("\(variants.count) 种")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(variants) { variant in
                                    NavigationLink {
                                        RecipeDetailView(recipe: variant)
                                    } label: {
                                        VariantCard(recipe: variant,
                                                    currentRecipeID: recipe.id,
                                                    sharedTags: Array(Set(variant.tags).intersection(Set(recipe.tags))))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .edgesIgnoringSafeArea(.top)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation {
                        store.toggleFavorite(id: recipe.id)
                    }
                } label: {
                    Image(systemName: store.isFavorite(id: recipe.id) ? "heart.fill" : "heart")
                        .foregroundColor(store.isFavorite(id: recipe.id) ? .red : .primary)
                }
            }
        }
    }

    /// 顶部 Hero 封面区：cover 为空串走静态占位（同 RecipeCardView 逻辑）
    /// 优先 bundle 本地图片，fallback 远程 cover URL
    @ViewBuilder
    private var heroImage: some View {
        let slug = BundleImage.slugify(recipe.name)
        if let localImage = BundleImage.lookup(cuisine: recipe.cuisine, slug: slug) {
            Image(uiImage: localImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if recipe.cover.isEmpty {
            ZStack {
                LinearGradient(
                    colors: [Color.orange, Color.red],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "frying.pan.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.8))
            }
        } else {
            AsyncImage(url: URL(string: recipe.cover)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    ZStack {
                        LinearGradient(
                            colors: [Color.orange, Color.red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: "frying.pan.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.8))
                    }
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}

// MARK: - Metric Item Helper
private struct MetricItem: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Ingredient Badge Helper
private struct IngredientBadge: View {
    let ingredient: Ingredient
    let multiplier: Double
    let isMain: Bool

    var body: some View {
        HStack {
            Text(ingredient.name)
                .font(.subheadline)
                .fontWeight(isMain ? .bold : .regular)
                .foregroundColor(.primary)

            Spacer()

            Text(ingredient.formattedAmount(multiplier: multiplier))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(isMain ? .orange : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(isMain ? Color.orange.opacity(0.08) : Color.tertiarySystemGroupedBg))
    }
}

// MARK: - Variant Card
/// 口味变体宫格中的一张卡片。
/// 不同口味/工艺但同主题的菜，点哪个切到哪个详情页。
struct VariantCard: View {
    let recipe: Recipe
    let currentRecipeID: Int
    let sharedTags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 封面图
            variantCover
            .frame(width: 150, height: 90)
            .clipped()
            .cornerRadius(10)

            // 菜名
            Text(recipe.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            // 共享 tag (被当前菜“共享”的)
            if !sharedTags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(sharedTags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple.opacity(0.18)))
                            .foregroundColor(.purple)
                    }
                    if sharedTags.count > 2 {
                        Text("+\(sharedTags.count - 2)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tertiarySystemGroupedBg))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(currentRecipeID == recipe.id ? Color.purple : Color.clear, lineWidth: 2)
        )
    }

    @ViewBuilder
    private var variantCover: some View {
        let slug = BundleImage.slugify(recipe.name)
        if let localImage = BundleImage.lookup(cuisine: recipe.cuisine, slug: slug) {
            Image(uiImage: localImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if recipe.cover.isEmpty {
            ZStack {
                LinearGradient(colors: [.purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "fork.knife").foregroundColor(.white.opacity(0.7)).font(.title2)
            }
        } else {
            AsyncImage(url: URL(string: recipe.cover)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    ZStack {
                        LinearGradient(colors: [.purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "fork.knife").foregroundColor(.white.opacity(0.7)).font(.title2)
                    }
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}
