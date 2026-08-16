//
//  RootView.swift
//  GameVerse
//

import SwiftUI

/// Gates the app: shows first-run setup until the Wine runtime is installed,
/// then the main library.
struct RootView: View {
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        Group {
            if library.runtimeReady {
                LibraryView()
            } else {
                SetupView()
            }
        }
        .sheet(isPresented: $library.isCreatingBottle) {
            NewBottleSheet()
        }
    }
}
