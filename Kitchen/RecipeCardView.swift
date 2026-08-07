//
//  RecipeCardView.swift
//  Kitchen
//
//  Created by 衡敏涛 on 2026/8/4.
//

import SwiftUI

struct RecipeCardView: View {
    let recipe: Recipe
    @EnvironmentObject var store: RecipeStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Image Container
            ZStack(alignment: .topTrailing) {
                coverContent
                .frame(height: 160)
                .clipped()
                
                // Cuisine Badge
                HStack {
                    Text(recipe.cuisine)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(8)
                    
                    Spacer()
                    
                    // Favorite Heart Button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            store.toggleFavorite(id: recipe.id)
                        }
                    } label: {
                        Image(systemName: store.isFavorite(id: recipe.id) ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(store.isFavorite(id: recipe.id) ? .red : .white)
                            .padding(8)
                            .background(Circle().fill(.ultraThinMaterial))
                            .shadow(radius: 2)
                    }
                    .padding(8)
                }
            }
            
            // Card Content Body
            VStack(alignment: .leading, spacing: 8) {
                Text(recipe.name)
                    .font(.title3)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                // Meta Info Bar
                HStack(spacing: 12) {
                    Label("\(recipe.duration)分钟", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label(recipe.difficultyText, systemImage: "chart.bar.fill")
                        .font(.caption)
                        .foregroundColor(difficultyColor(for: recipe.difficulty))

                    if recipe.calories > 0 {
                        Label("\(recipe.calories)千卡", systemImage: "flame.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                // Tag Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(recipe.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color.orange.opacity(0.18))
                                        .overlay(Capsule().stroke(Color.orange.opacity(0.5), lineWidth: 1))
                                )
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(Color.secondarySystemGroupedBg)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
    }

    /// 封面区：cover 为空时走静态占位分支，避免 URL(string:"") 返 nil
    /// 造成某些 iOS 版本上 AsyncImage 不渲染的“首页有坑”问题。
    @ViewBuilder
    private var coverContent: some View {
        if recipe.cover.isEmpty {
            ZStack {
                LinearGradient(
                    colors: [Color.orange.opacity(0.6), Color.red.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 8) {
                    Image(systemName: "frying.pan.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                    Text(recipe.name)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
            }
        } else {
            AsyncImage(url: URL(string: recipe.cover)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    ZStack {
                        LinearGradient(
                            colors: [Color.orange.opacity(0.6), Color.red.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        VStack(spacing: 8) {
                            Image(systemName: "frying.pan.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.white)
                            Text(recipe.name)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}
