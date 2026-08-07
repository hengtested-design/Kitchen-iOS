//
//  KitchenApp.swift
//  Kitchen
//
//  Created by 衡敏涛 on 2026/8/4.
//

import SwiftUI

@main
struct KitchenApp: App {
    @StateObject private var recipeStore = RecipeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recipeStore)
        }
    }
}
