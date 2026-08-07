//
//  Models.swift
//  Kitchen
//
//  Created by 衡敏涛 on 2026/8/4.
//

import Foundation

// MARK: - Ingredient

struct Ingredient: Identifiable, Codable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let amount: Double
    let unit: String
    let isMain: Bool
    
    // Formatted amount taking into account serving multiplier
    func formattedAmount(multiplier: Double = 1.0) -> String {
        let scaledAmount = amount * multiplier
        // 如果 amount 为 0(如外部源数据是中文量词而非数字),直接显示 unit
        if scaledAmount == 0 {
            return unit
        }
        if scaledAmount.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(scaledAmount)) \(unit)"
        } else {
            return String(format: "%.1f %@", scaledAmount, unit)
        }
    }
}

// MARK: - RecipeStep

struct RecipeStep: Identifiable, Codable, Hashable, Sendable {
    var id: Int { number }
    let number: Int
    let description: String
    let tips: String?
}

// MARK: - Recipe

struct Recipe: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    var name: String
    var cuisine: String
    var cover: String
    var difficulty: Int
    var duration: Int
    var servings: Int
    var calories: Int
    var ingredients: [Ingredient]
    var steps: [RecipeStep]
    var tips: String?
    var tags: [String]
    
    var difficultyText: String {
        switch difficulty {
        case 1: return "简单"
        case 2: return "中等"
        case 3: return "困难"
        case 4: return "复杂"
        case 5: return "大师"
        default: return "未知"
        }
    }
}

// MARK: - Filter Enums

enum CuisineFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case chuan = "川菜"
    case yue = "粤菜"
    case xiang = "湘菜"
    case zhe = "浙菜"
    case jiachang = "家常菜"
    case liang = "凉菜"
    case xican = "西餐"

    var id: String { rawValue }
}

enum DifficultyFilter: Int, CaseIterable, Identifiable, Sendable {
    case all = 0
    case easy = 1
    case medium = 2
    case hard = 3
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .all: return "全部难度"
        case .easy: return "简单"
        case .medium: return "中等"
        case .hard: return "困难"
        }
    }
}

enum DurationFilter: Int, CaseIterable, Identifiable, Sendable {
    case all = 0
    case under15 = 15
    case under30 = 30
    case under60 = 60
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .all: return "全部时长"
        case .under15: return "15分钟内"
        case .under30: return "30分钟内"
        case .under60: return "60分钟内"
        }
    }
}