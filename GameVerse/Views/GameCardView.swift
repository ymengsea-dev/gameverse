//
//  GameCardView.swift
//  GameVerse
//

import SwiftUI

/// One launchable item in the grid: icon, title, and a Play button on hover.
struct GameCardView: View {
    @EnvironmentObject private var library: LibraryModel
    let item: GameItem
    var showsBottle: Bool = false

    @State private var hovering = false
    @State private var launching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                cover
                if hovering || launching {
                    Color.black.opacity(0.35)
                    Button(action: play) {
                        Label(launching ? "Launching…" : "Play", systemImage: "play.fill")
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Theme.brandGradient, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(launching)
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.06)))
            .shadow(color: .black.opacity(hovering ? 0.35 : 0.15), radius: hovering ? 12 : 5, y: 4)

            Text(item.displayName)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            if showsBottle {
                Text(item.bottle.settings.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: play)
        .contextMenu {
            Button("Play", action: play)
            if case .program = item.source {
                Button("Remove from Library", role: .destructive) {
                    library.removeProgram(item)
                }
            }
        }
    }

    @ViewBuilder
    private var cover: some View {
        ZStack {
            Theme.tilePlaceholder
            if let icon = item.icon {
                // Fit + center so small app icons aren't blown up or cropped.
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 96, maxHeight: 96)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func play() {
        guard !launching else { return }
        launching = true
        Task {
            await library.launch(item)
            try? await Task.sleep(for: .seconds(3))
            launching = false
        }
    }
}
