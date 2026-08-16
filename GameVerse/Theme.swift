//
//  Theme.swift
//  GameVerse
//

import SwiftUI

/// GameVerse visual language: an indigo→violet brand accent used sparingly for
/// primary actions and highlights, on top of the system's material chrome.
enum Theme {
    static let accent = Color(red: 0.42, green: 0.36, blue: 0.90)
    static let accentSoft = Color(red: 0.55, green: 0.48, blue: 0.96)

    static let brandGradient = LinearGradient(
        colors: [accent, accentSoft],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Placeholder tile shown for a game with no cached icon.
    static let tilePlaceholder = LinearGradient(
        colors: [Color(white: 0.22), Color(white: 0.14)],
        startPoint: .top,
        endPoint: .bottom
    )
}
