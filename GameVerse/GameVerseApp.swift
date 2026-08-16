//
//  GameVerseApp.swift
//  GameVerse
//

import SwiftUI

@main
struct GameVerseApp: App {
    @StateObject private var library = LibraryModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .frame(minWidth: 820, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Bottle…") { library.isCreatingBottle = true }
                    .keyboardShortcut("n")
            }
        }
    }
}
