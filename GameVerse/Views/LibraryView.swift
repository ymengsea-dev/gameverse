//
//  LibraryView.swift
//  GameVerse
//

import SwiftUI
import GVEngine

/// What the detail pane is showing.
enum LibrarySection: Hashable {
    case allGames
    case bottle(Bottle)
}

/// Main window: a sidebar of the library shelf + bottles, and a grid detail.
struct LibraryView: View {
    @EnvironmentObject private var library: LibraryModel
    @State private var selection: LibrarySection = .allGames

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Library") {
                    Label("All Games", systemImage: "square.grid.2x2")
                        .tag(LibrarySection.allGames)
                }
                Section("Bottles") {
                    ForEach(library.bottles) { bottle in
                        Label(bottle.settings.name, systemImage: "cube")
                            .tag(LibrarySection.bottle(bottle))
                            .contextMenu {
                                Button("Delete Bottle", role: .destructive) {
                                    library.delete(bottle)
                                    selection = .allGames
                                }
                            }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .safeAreaInset(edge: .bottom) {
                Button {
                    library.isCreatingBottle = true
                } label: {
                    Label("New Bottle", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
        } detail: {
            switch selection {
            case .allGames:
                GameGridView(title: "All Games", items: library.allItems, showsBottle: true)
            case .bottle(let bottle):
                BottleLibraryView(bottle: bottle)
            }
        }
        .navigationTitle("GameVerse")
    }
}

/// Per-bottle detail. Observes the bottle so pinning/removing a game refreshes
/// the grid immediately.
private struct BottleLibraryView: View {
    @EnvironmentObject private var library: LibraryModel
    @ObservedObject var bottle: Bottle

    var body: some View {
        GameGridView(title: bottle.settings.name, items: library.items(in: bottle), bottle: bottle)
    }
}
