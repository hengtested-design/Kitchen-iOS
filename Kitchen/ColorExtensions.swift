//
//  ColorExtensions.swift
//  Kitchen
//
//  Cross-platform Color helpers. Kept in a separate file so that
// data models (Recipe/Ingredient/RecipeStep) don't accidentally
// inherit @MainActor isolation from SwiftUI's Color type.
//

import SwiftUI

extension Color {
    #if canImport(UIKit)
    static let systemGroupedBg = Color(UIColor.systemGroupedBackground)
    static let secondarySystemGroupedBg = Color(UIColor.secondarySystemGroupedBackground)
    static let tertiarySystemGroupedBg = Color(UIColor.tertiarySystemGroupedBackground)
    static let systemBg = Color(UIColor.systemBackground)
    #else
    static let systemGroupedBg = Color(NSColor.windowBackgroundColor)
    static let secondarySystemGroupedBg = Color(NSColor.controlBackgroundColor)
    static let tertiarySystemGroupedBg = Color(NSColor.underPageBackgroundColor)
    static let systemBg = Color(NSColor.windowBackgroundColor)
    #endif
}

// MARK: - Recipe UI Helpers
// Difficulty → Color mapping lives in the UI layer so the Recipe model
// can stay plain Codable without SwiftUI's @MainActor isolation.

func difficultyColor(for difficulty: Int) -> Color {
    switch difficulty {
    case 1: return .green
    case 2: return .orange
    case 3: return .red
    default: return .gray
    }
}