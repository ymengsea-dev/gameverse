//
//  StorageView.swift
//  GameVerse
//

import SwiftUI
import GVEngine

/// Bottle-scoped game storage embedded in the bottle settings form. Filesystem
/// traversal runs away from the main actor so large games do not block the UI.
struct BottleStorageSection: View {
    private struct Measurement: Sendable {
        let sizes: [String: Int64]
        let unavailable: Set<String>
    }

    @EnvironmentObject private var library: LibraryModel
    @ObservedObject var bottle: Bottle
    @State private var items: [GameStorageItem] = []
    @State private var sizes: [String: Int64] = [:]
    @State private var unavailable: Set<String> = []
    @State private var isScanning = false

    private var measuredTotal: Int64 {
        sizes.values.reduce(0, +)
    }

    var body: some View {
        Section("Game Storage") {
            if isScanning && items.isEmpty {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Calculating…")
                        .foregroundStyle(.secondary)
                }
            } else if items.isEmpty {
                Text("No installed games")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Total", value: formattedSize(measuredTotal))
                ForEach(items) { item in
                    storageRow(item)
                }
            }

            HStack {
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isScanning)
                Spacer()
                if isScanning && !items.isEmpty {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .task(id: bottle.id) { await refresh() }
    }

    private func storageRow(_ item: GameStorageItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body.weight(.medium))
                Text(item.installationURL.path(percentEncoded: false))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 16)

            Group {
                if let size = sizes[item.id] {
                    Text(formattedSize(size))
                } else if unavailable.contains(item.id) {
                    Text("Folder unavailable")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .font(.callout.monospacedDigit())

            Button {
                NSWorkspace.shared.open(item.installationURL)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .disabled(unavailable.contains(item.id))
            .help("Open Game Folder")
        }
    }

    @MainActor
    private func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let currentItems = library.storageItems(in: bottle)
        items = currentItems
        sizes = [:]
        unavailable = []

        let measurement = await Task.detached(priority: .utility) {
            var measured: [String: Int64] = [:]
            var unavailable: Set<String> = []
            for item in currentItems {
                do {
                    measured[item.id] = try StorageScanner.logicalSize(of: item.installationURL)
                } catch {
                    unavailable.insert(item.id)
                }
            }
            return Measurement(sizes: measured, unavailable: unavailable)
        }.value

        sizes = measurement.sizes
        unavailable = measurement.unavailable
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
