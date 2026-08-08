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

    // 容错解码: 缺字段时用默认值, 不让整条菜因配料缺失而拒绝
    init(name: String, amount: Double, unit: String, isMain: Bool) {
        self.name = name
        self.amount = amount
        self.unit = unit
        self.isMain = isMain
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name     = (try? c.decode(String.self, forKey: .name)) ?? "未知"
        self.amount   = (try? c.decode(Double.self, forKey: .amount)) ?? 0
        self.unit     = (try? c.decode(String.self, forKey: .unit)) ?? ""
        self.isMain   = (try? c.decode(Bool.self,   forKey: .isMain)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case name, amount, unit, isMain
    }

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

    init(number: Int, description: String, tips: String? = nil) {
        self.number = number
        self.description = description
        self.tips = tips
    }

    // 容错解码: 缺 description 时降级为空串, 缺 tips 时为 nil
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.number      = (try? c.decode(Int.self,    forKey: .number))      ?? 0
        self.description = (try? c.decode(String.self, forKey: .description)) ?? ""
        self.tips        = try? c.decodeIfPresent(String.self, forKey: .tips)
    }

    private enum CodingKeys: String, CodingKey {
        case number, description, tips
    }
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

    // 容错解码 — 核心修复:
    //   HowToCook / 部分源数据缺 cover / ingredients / steps 等字段。
    //   Swift 默认 Codable 遇到 keyNotFound 会拒绝整条菜，导致 5 个菜系全废，
    //   UI 只剩 3 道菜。这里所有字段用 decodeIfPresent，缺则用安全默认值。
    init(
        id: Int, name: String, cuisine: String, cover: String,
        difficulty: Int, duration: Int, servings: Int, calories: Int,
        ingredients: [Ingredient], steps: [RecipeStep],
        tips: String?, tags: [String]
    ) {
        self.id = id
        self.name = name
        self.cuisine = cuisine
        self.cover = cover
        self.difficulty = difficulty
        self.duration = duration
        self.servings = servings
        self.calories = calories
        self.ingredients = ingredients
        self.steps = steps
        self.tips = tips
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id          = (try? c.decode(Int.self,    forKey: .id))          ?? 0
        self.name        = (try? c.decode(String.self, forKey: .name))        ?? "未命名"
        self.cuisine     = (try? c.decode(String.self, forKey: .cuisine))     ?? "其他"
        self.cover       = (try? c.decode(String.self, forKey: .cover))       ?? ""
        self.difficulty  = (try? c.decode(Int.self,    forKey: .difficulty))  ?? 1
        self.duration    = (try? c.decode(Int.self,    forKey: .duration))    ?? 30
        self.servings    = (try? c.decode(Int.self,    forKey: .servings))    ?? 2
        self.calories    = (try? c.decode(Int.self,    forKey: .calories))    ?? 0
        self.ingredients = (try? c.decode([Ingredient].self, forKey: .ingredients)) ?? []
        self.steps       = (try? c.decode([RecipeStep].self,  forKey: .steps))       ?? []
        self.tips        = try? c.decodeIfPresent(String.self, forKey: .tips)
        self.tags        = (try? c.decode([String].self, forKey: .tags)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, cuisine, cover, difficulty, duration, servings
        case calories, ingredients, steps, tips, tags
    }

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

/// 菜系筛选器 — “全部” + 动态菜系名（从实际数据中计算）
/// 之前是固定 enum, 导致数据和 chip 不对齐 (如 “凉菜” 不存在, “东北” 造法)。
/// 现在以 `availableCuisines` (动态) 为主, `all` 作为唯一固定项。
struct CuisineFilter: Identifiable, Hashable, Sendable {
    let name: String  // "全部" / "川菜" / "东北" ...
    var id: String { name }

    static let all = CuisineFilter(name: "全部")

    /// 从菜谱列表生成所有菜系 (按菜数降序, “全部” 排首位)
    static func from(recipes: [Recipe]) -> [CuisineFilter] {
        var counts: [String: Int] = [:]
        for r in recipes {
            counts[r.cuisine, default: 0] += 1
        }
        let sorted = counts.sorted { $0.value > $1.value }.map { CuisineFilter(name: $0.key) }
        return [CuisineFilter.all] + sorted
    }
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