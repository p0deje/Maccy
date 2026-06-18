import AppKit
import Foundation

enum ScriptRunnerError: Error {
  case notFound(String)
  case timedOut(String)
}

// Watches a directory and invokes `onChange` whenever its entries change (files added,
// removed, or renamed). Used to keep the scripts picker in sync while the settings pane is open.
final class DirectoryWatcher {
  private let url: URL
  private let onChange: () -> Void
  private var source: DispatchSourceFileSystemObject?
  private var fileDescriptor: CInt = -1

  init(url: URL, onChange: @escaping () -> Void) {
    self.url = url
    self.onChange = onChange
  }

  func start() {
    guard source == nil else { return }

    fileDescriptor = open(url.path, O_EVTONLY)
    guard fileDescriptor >= 0 else { return }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fileDescriptor,
      eventMask: [.write, .delete, .rename],
      queue: .main
    )
    source.setEventHandler { [onChange] in onChange() }
    source.setCancelHandler { [fileDescriptor] in
      if fileDescriptor >= 0 { close(fileDescriptor) }
    }
    self.source = source
    source.resume()
  }

  func stop() {
    source?.cancel()
    source = nil
    fileDescriptor = -1
  }

  deinit {
    stop()
  }
}

// Abstraction so `AutomationProcessor` can be unit-tested with a stub instead of really
// spawning a script.
protocol ScriptRunning {
  func run(scriptName: String, input: String) async throws -> String
}

// Runs user shell scripts via `NSUserUnixTask`.
//
// Scripts must live in `~/Library/Application Scripts/<bundle-id>/`. macOS executes them
// *outside* the app sandbox (via lsboxd/XPC), so they get the user's normal privileges —
// network, filesystem, Homebrew tools — while Maccy itself stays sandboxed. A sandboxed app
// may read/list and run scripts in this directory without any extra entitlement; it just
// cannot write to it (the user installs scripts there themselves).
final class ScriptRunner: ScriptRunning {
  static let shared = ScriptRunner()

  // Overridable so tests can point at a temporary directory.
  var scriptsDirectoryProvider: () -> URL? = {
    try? FileManager.default.url(
      for: .applicationScriptsDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
  }

  var timeout: TimeInterval = 30

  var scriptsDirectory: URL? { scriptsDirectoryProvider() }

  // Filenames of the scripts the user has installed, for display in the settings picker.
  func availableScripts() -> [String] {
    guard let directory = scriptsDirectory,
          let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
      return []
    }

    return names
      .filter { !$0.hasPrefix(".") }
      .sorted()
  }

  // Opens the scripts directory in Finder so the user can drop scripts in.
  func reveal() {
    guard let directory = scriptsDirectory else { return }
    NSWorkspace.shared.activateFileViewerSelecting([directory])
  }

  func run(scriptName: String, input: String) async throws -> String {
    guard let directory = scriptsDirectory else {
      throw ScriptRunnerError.notFound(scriptName)
    }

    let scriptURL = directory.appendingPathComponent(scriptName)
    guard FileManager.default.fileExists(atPath: scriptURL.path) else {
      throw ScriptRunnerError.notFound(scriptName)
    }

    let task = try NSUserUnixTask(url: scriptURL)
    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    task.standardInput = stdinPipe.fileHandleForReading
    task.standardOutput = stdoutPipe.fileHandleForWriting
    task.standardError = stderrPipe.fileHandleForWriting

    return try await withThrowingTaskGroup(of: String.self) { group in
      group.addTask {
        try await Self.execute(
          task,
          input: input,
          stdin: stdinPipe,
          stdout: stdoutPipe,
          stderr: stderrPipe
        )
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
        throw ScriptRunnerError.timedOut(scriptName)
      }

      defer { group.cancelAll() }
      // Return whichever finishes first: the script output or the timeout error.
      guard let result = try await group.next() else {
        throw ScriptRunnerError.timedOut(scriptName)
      }
      return result
    }
  }

  private static func execute(
    _ task: NSUserUnixTask,
    input: String,
    stdin: Pipe,
    stdout: Pipe,
    stderr: Pipe
  ) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      let group = DispatchGroup()
      var outputData = Data()
      var runError: Error?

      // Drain stdout concurrently so a script producing more than the pipe buffer (~64KB)
      // can't block waiting for us to read.
      group.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        group.leave()
      }

      group.enter()
      task.execute(withArguments: nil) { error in
        runError = error
        group.leave()
      }

      // Feed the clipboard text in and signal EOF.
      let writeHandle = stdin.fileHandleForWriting
      writeHandle.write(Data(input.utf8))
      try? writeHandle.close()

      // Close our copies of the write ends so the stdout reader receives EOF once the
      // script (the only remaining writer) exits.
      try? stdout.fileHandleForWriting.close()
      try? stderr.fileHandleForWriting.close()

      group.notify(queue: .global()) {
        if let runError {
          continuation.resume(throwing: runError)
        } else {
          continuation.resume(returning: String(decoding: outputData, as: UTF8.self))
        }
      }
    }
  }
}
