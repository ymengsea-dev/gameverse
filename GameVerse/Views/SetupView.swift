//
//  SetupView.swift
//  GameVerse
//

import SwiftUI
import GVEngine

/// First-run setup: make sure Rosetta and the bundled Wine runtime are present
/// before the library can run anything.
struct SetupView: View {
    @EnvironmentObject private var library: LibraryModel
    @State private var rosettaInstalled = Rosetta2.isRosettaInstalled
    @State private var installingRuntime = false
    @State private var installingRosetta = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.brandGradient)
            Text("Welcome to GameVerse")
                .font(.largeTitle.bold())
            Text("A couple of things are needed before your first game.")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                requirementRow(
                    title: "Rosetta 2",
                    detail: "Runs the x86_64 Wine runtime on Apple Silicon.",
                    done: rosettaInstalled,
                    busy: installingRosetta,
                    action: installRosetta
                )
                requirementRow(
                    title: "Wine Runtime",
                    detail: "The translation layer that runs Windows games.",
                    done: library.runtimeReady,
                    busy: installingRuntime,
                    action: installRuntime
                )
            }
            .frame(maxWidth: 460)

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
        .padding(40)
    }

    private func requirementRow(
        title: String, detail: String, done: Bool, busy: Bool, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title2)
                .foregroundStyle(done ? .green : .secondary)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if busy {
                ProgressView().controlSize(.small)
            } else if !done {
                Button("Install", action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func installRosetta() {
        installingRosetta = true
        Task {
            defer { installingRosetta = false }
            do {
                rosettaInstalled = try await Rosetta2.installRosetta()
            } catch {
                self.error = "Rosetta install failed: \(error.localizedDescription)"
            }
        }
    }

    private func installRuntime() {
        guard let source = WineRuntimeSource.tarballURL else {
            error = "No Wine runtime source configured."
            return
        }
        installingRuntime = true
        Task.detached {
            // install(from:) deletes the tarball it's given, so hand it a copy.
            let temp = FileManager.default.temporaryDirectory.appending(path: source.lastPathComponent)
            do {
                try? FileManager.default.removeItem(at: temp)
                try FileManager.default.copyItem(at: source, to: temp)
                try WineRuntimeInstaller.install(from: temp)
                await MainActor.run {
                    installingRuntime = false
                    library.reload()
                }
            } catch {
                await MainActor.run {
                    installingRuntime = false
                    self.error = "Wine runtime install failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
