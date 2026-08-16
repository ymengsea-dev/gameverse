//
//  GameGridView.swift
//  GameVerse
//

import SwiftUI
import UniformTypeIdentifiers
import GVEngine

/// A responsive grid of launchable items. When shown for a specific bottle it
/// offers per-bottle actions (add a game/app, bottle settings, and — only if
/// Steam is installed there — repair Steam).
struct GameGridView: View {
    @EnvironmentObject private var library: LibraryModel

    let title: String
    let items: [GameItem]
    var bottle: Bottle?
    var showsBottle: Bool = false

    @State private var showingInspector = false

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 20)]

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(items) { item in
                            GameCardView(item: item, showsBottle: showsBottle)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle(title)
        .toolbar { toolbar }
        .sheet(isPresented: $showingInspector) {
            if let bottle { BottleInspectorView(bottle: bottle) }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Games or Apps Yet", systemImage: "square.grid.2x2")
        } description: {
            Text(bottle == nil
                 ? "Create a bottle and add a game or app to get started."
                 : "Add any Windows game or app to this bottle to see it here.")
        } actions: {
            if let bottle {
                Button("Add a Game or App…") { addProgram(to: bottle) }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let bottle {
            ToolbarItemGroup {
                Button {
                    addProgram(to: bottle)
                } label: {
                    Label("Add Game", systemImage: "plus")
                }
                Button {
                    showingInspector = true
                } label: {
                    Label("Bottle Settings", systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    /// Pick any Windows executable and pin it to the bottle as a game/app.
    private func addProgram(to bottle: Bottle) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .data]
        panel.directoryURL = bottle.url.appending(path: "drive_c")
        if panel.runModal() == .OK, let url = panel.url {
            library.addProgram(url: url, to: bottle)
        }
    }
}
