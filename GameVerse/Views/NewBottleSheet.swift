//
//  NewBottleSheet.swift
//  GameVerse
//

import SwiftUI
import GVEngine

/// Create a new Wine bottle (prefix) to install games into.
struct NewBottleSheet: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = "New Bottle"
    @State private var winVersion: WinVersion = .win10

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Bottle").font(.title2.bold())

            Form {
                TextField("Name", text: $name)
                Picker("Windows Version", selection: $winVersion) {
                    ForEach(WinVersion.allCases, id: \.self) { version in
                        Text(version.pretty()).tag(version)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create") {
                    library.createBottle(name: name.isEmpty ? "New Bottle" : name, winVersion: winVersion)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
