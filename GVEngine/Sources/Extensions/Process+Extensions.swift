//
//  Process+Extensions.swift
//  GVEngine
//
//  This file is part of GameVerse, a fork of Whisky
//  (https://github.com/Whisky-App/Whisky) by Isaac Marovitz.
//
//  GameVerse is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  GameVerse is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with GameVerse.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import os.log

public enum ProcessOutput: Hashable {
    case started(Process)
    case message(String)
    case error(String)
    case terminated(Process)
}

public extension Process {
    /// Run the process returning a stream output
    func runStream(name: String, fileHandle: FileHandle?) throws -> AsyncStream<ProcessOutput> {
        let stream = makeStream(name: name, fileHandle: fileHandle)
        self.logProcessInfo(name: name)
        fileHandle?.writeInfo(for: self)
        try run()
        return stream
    }

    private func makeStream(name: String, fileHandle: FileHandle?) -> AsyncStream<ProcessOutput> {
        let pipe = Pipe()
        let errorPipe = Pipe()
        standardOutput = pipe
        standardError = errorPipe

        return AsyncStream<ProcessOutput> { continuation in
            continuation.onTermination = { termination in
                guard case .cancelled = termination, self.isRunning else { return }
                self.terminate()
            }

            continuation.yield(.started(self))

            pipe.fileHandleForReading.readabilityHandler = { pipe in
                guard let line = pipe.nextLine() else { return }
                continuation.yield(.message(line))
                guard !line.isEmpty else { return }
                Logger.wineKit.info("\(line, privacy: .public)")
                fileHandle?.write(line: line)
            }

            errorPipe.fileHandleForReading.readabilityHandler = { pipe in
                guard let line = pipe.nextLine() else { return }
                continuation.yield(.error(line))
                guard !line.isEmpty else { return }
                Logger.wineKit.warning("\(line, privacy: .public)")
                fileHandle?.write(line: line)
            }

            terminationHandler = { (process: Process) in
                process.finishStream(
                    pipe: pipe, errorPipe: errorPipe, fileHandle: fileHandle,
                    name: name, continuation: continuation
                )
            }
        }
    }

    /// Drain any buffered output still in the pipes, persist it and the
    /// termination summary, then close out the stream. A crashing child often
    /// writes its page-fault / backtrace in the last chunk before exit, so this
    /// drain is what makes crashes actually show up in the log.
    private func finishStream(
        pipe: Pipe, errorPipe: Pipe, fileHandle: FileHandle?, name: String,
        continuation: AsyncStream<ProcessOutput>.Continuation
    ) {
        // Stop the live handlers so they don't race the final drain below.
        pipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        do {
            drain(pipe.fileHandleForReading, isError: false, fileHandle: fileHandle, continuation: continuation)
            drain(errorPipe.fileHandleForReading, isError: true, fileHandle: fileHandle, continuation: continuation)
            logTermination(name: name, fileHandle: fileHandle)
            try fileHandle?.close()
        } catch {
            Logger.wineKit.error("Error while clearing data: \(error)")
        }

        continuation.yield(.terminated(self))
        continuation.finish()
    }

    private func drain(
        _ handle: FileHandle, isError: Bool, fileHandle: FileHandle?,
        continuation: AsyncStream<ProcessOutput>.Continuation
    ) {
        guard let data = try? handle.readToEnd(),
              let line = String(data: data, encoding: .utf8), !line.isEmpty else { return }
        continuation.yield(isError ? .error(line) : .message(line))
        if isError {
            Logger.wineKit.warning("\(line, privacy: .public)")
        } else {
            Logger.wineKit.info("\(line, privacy: .public)")
        }
        fileHandle?.write(line: line)
    }

    private func logTermination(name: String, fileHandle: FileHandle?) {
        let reasonText: String
        switch terminationReason {
        case .exit:
            reasonText = "exit"
        case .uncaughtSignal:
            reasonText = "uncaught signal (crash)"
        @unknown default:
            reasonText = "unknown"
        }

        let summary = "Process \(name) terminated: status=\(terminationStatus), reason=\(reasonText)"

        if terminationStatus == 0 {
            Logger.wineKit.info("\(summary, privacy: .public)")
        } else {
            Logger.wineKit.warning("\(summary, privacy: .public)")
        }

        // Persist the termination summary into the .log file so a crash leaves a
        // clear final line (exit code + crash-vs-clean) instead of ending mid-stream.
        fileHandle?.write(line: "\n\(summary)\n")
    }

    private func logProcessInfo(name: String) {
        Logger.wineKit.info("Running process \(name)")

        if let arguments = arguments {
            Logger.wineKit.info("Arguments: `\(arguments.joined(separator: " "))`")
        }
        if let executableURL = executableURL {
            Logger.wineKit.info("Executable: `\(executableURL.path(percentEncoded: false))`")
        }
        if let directory = currentDirectoryURL {
            Logger.wineKit.info("Directory: `\(directory.path(percentEncoded: false))`")
        }
        if let environment = environment {
            Logger.wineKit.info("Environment: \(environment)")
        }
    }
}

extension FileHandle {
    func nextLine() -> String? {
        guard let line = String(data: availableData, encoding: .utf8) else { return nil }
        if !line.isEmpty {
            return line
        } else {
            return nil
        }
    }
}
