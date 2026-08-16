//
//  BottleInspectorView.swift
//  GameVerse
//

import SwiftUI
import GVEngine

/// Lightweight, game-launcher-focused bottle settings: just the knobs that
/// matter for getting games running. The full Wine config surface stays in the
/// engine for power users.
struct BottleInspectorView: View {
    @EnvironmentObject private var library: LibraryModel
    @ObservedObject var bottle: Bottle
    @Environment(\.dismiss) private var dismiss

    @State private var confirmingDelete = false

    /// Whether this bottle actually has a Steam install (so "Repair Steam" is relevant).
    private var hasSteam: Bool {
        let steamExe = SteamLibrary.steamRoot(in: bottle).appending(path: "steam.exe")
        return FileManager.default.fileExists(atPath: steamExe.path(percentEncoded: false))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Bottle Settings").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()

            Form {
                Section {
                    TextField("Name", text: $bottle.settings.name)
                    Picker("Windows Version", selection: $bottle.settings.windowsVersion) {
                        ForEach(WinVersion.allCases, id: \.self) { Text($0.pretty()).tag($0) }
                    }
                    // Show the actual bundled runtime, not the per-bottle stored value
                    // (older bottles may still record the Wine version they were first
                    // booted with — every bottle runs the current bundled Wine).
                    LabeledContent("Wine Version",
                                   value: (WineRuntimeInstaller.wineRuntimeVersion()
                                           ?? WineRuntimeInstaller.bundledWineVersion).description)
                }

                Section("Graphics") {
                    Toggle("DXVK (Direct3D → Vulkan)", isOn: $bottle.settings.dxvk)
                }

                Section {
                    Button("Show C: Drive in Finder") {
                        NSWorkspace.shared.open(bottle.url.appending(path: "drive_c"))
                    }
                    // Only meaningful once Steam is actually installed in this bottle.
                    if hasSteam {
                        Button("Repair Steam") { library.repairSteam(in: bottle) }
                    }
                }

                Section {
                    Button("Delete Bottle", role: .destructive) { confirmingDelete = true }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 460, height: 460)
        .confirmationDialog("Delete this bottle and all its games?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                library.delete(bottle)
                dismiss()
            }
        }
    }
}
