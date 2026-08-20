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
    private enum FocusedField: Hashable {
        case name
    }

    @EnvironmentObject private var library: LibraryModel
    @ObservedObject var bottle: Bottle
    @Environment(\.dismiss) private var dismiss

    @State private var draftSettings: BottleSettings
    @State private var detectedWineVersion: String?
    @State private var runtimeDetectionFailed = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var confirmingDelete = false
    @FocusState private var focusedField: FocusedField?

    init(bottle: Bottle) {
        self.bottle = bottle
        _draftSettings = State(initialValue: bottle.settings)
    }

    /// Whether this bottle actually has a Steam install (so "Repair Steam" is relevant).
    private var hasSteam: Bool {
        let steamExe = SteamLibrary.steamRoot(in: bottle).appending(path: "steam.exe")
        return FileManager.default.fileExists(atPath: steamExe.path(percentEncoded: false))
    }

    private var trimmedName: String {
        draftSettings.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasUnsavedChanges: Bool {
        draftSettings != bottle.settings
    }

    private var graphicsRenderer: String {
        draftSettings.graphicsRenderer.displayName
    }

    private var graphicsPipeline: String {
        draftSettings.graphicsRenderer.translationPath
    }

    private var rendererAvailability: GraphicsRendererAvailability {
        Wine.graphicsRendererAvailability
    }

    private var installedItems: [InstalledBottleItem] {
        library.installedItems(in: bottle)
    }

    private func rendererIsAvailable(_ renderer: GraphicsRenderer) -> Bool {
        switch renderer {
        case .auto, .wineD3D: return true
        case .d3dMetal: return rendererAvailability.d3dMetal
        case .dxmt: return rendererAvailability.dxmt
        case .dxvk: return rendererAvailability.dxvk
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Bottle Settings").font(.title2.bold())
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(!hasUnsavedChanges || trimmedName.isEmpty || isSaving)
            }
            .padding()

            Form {
                Section {
                    TextField("Name", text: $draftSettings.name)
                        .focused($focusedField, equals: .name)
                    Picker("Windows Version", selection: $draftSettings.windowsVersion) {
                        ForEach(WinVersion.allCases, id: \.self) { Text($0.pretty()).tag($0) }
                    }
                    LabeledContent("Engine") {
                        if let detectedWineVersion {
                            Text("Wine \(detectedWineVersion)")
                        } else if runtimeDetectionFailed {
                            Text("Unavailable").foregroundStyle(.secondary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                }

                Section("Graphics") {
                    Picker("Direct3D Renderer", selection: $draftSettings.graphicsRenderer) {
                        ForEach(GraphicsRenderer.allCases, id: \.self) { renderer in
                            Text(renderer.displayName)
                                .tag(renderer)
                                .disabled(!rendererIsAvailable(renderer))
                        }
                    }
                    LabeledContent("Configured Renderer", value: graphicsRenderer)
                    LabeledContent("Translation Path", value: graphicsPipeline)
                    Toggle("Show Metal Performance HUD", isOn: $draftSettings.metalHud)
                }

                Section {
                    if installedItems.isEmpty {
                        Text("No installed apps or games were detected.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(installedItems) { item in
                            HStack(spacing: 10) {
                                Group {
                                    if let icon = item.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .scaledToFit()
                                    } else {
                                        Image(systemName: "app.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).lineLimit(1)
                                    if let detailLabel = item.kind.detailLabel {
                                        Text(detailLabel)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([item.location])
                                } label: {
                                    Image(systemName: "folder")
                                }
                                .buttonStyle(.borderless)
                                .help("Show in Finder")
                            }
                        }
                    }
                } header: {
                    Text("Installed Content (\(installedItems.count))")
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
        .frame(width: 520, height: 680)
        .onAppear {
            // A TextField is the first focusable control in this sheet, so
            // AppKit otherwise selects its entire value as the sheet opens.
            DispatchQueue.main.async { focusedField = nil }
        }
        .task {
            do {
                detectedWineVersion = try await Wine.wineVersion()
            } catch {
                runtimeDetectionFailed = true
            }
        }
        .alert("Could Not Save Bottle Settings", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Unknown error")
        }
        .confirmationDialog("Delete this bottle and all its games?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                library.delete(bottle)
                dismiss()
            }
        }
    }

    @MainActor
    private func save() async {
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            if draftSettings.windowsVersion != bottle.settings.windowsVersion {
                try await Wine.changeWinVersion(bottle: bottle, win: draftSettings.windowsVersion)
            }
            draftSettings.name = trimmedName
            bottle.settings = draftSettings
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
