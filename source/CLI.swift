import ArgumentParser
import Foundation

@main
struct CLI: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "alternator", version: "2.1.0")

  @Argument(help: "Relative path to your source directory.", completion: .directory)
  var source: String

  @Argument(help: "Relative path to your target directory.", completion: .directory)
  var target: String

  @Flag(name: .shortAndLong, help: "Rebuild <source> as you make changes.")
  var watch = false

  @Option(name: .shortAndLong, help: "Serve <target> on localhost:<port>.")
  var port: UInt16?

  func validate() throws {
    Project.source = URL(string: source.asRef, relativeTo: URL.currentDirectory())
    Project.target = URL(string: target.asRef, relativeTo: URL.currentDirectory())

    guard Project.source!.exists
    else { throw ValidationError("<source> does not exist.") }

    guard Project.source!.isDirectory
    else { throw ValidationError("<source> must be a directory.") }

    guard Project.source!.masked != Project.target!.masked
    else { throw ValidationError("<source> and <target> cannot be the same directory.") }

    guard !Project.target!.exists || Project.target!.isDirectory
    else { throw ValidationError("<target> must be a directory.") }
  }

  mutating func run() throws {
    Project.build()

    if watch == true {
      startWatcher()
      CLI.log("[watch] watching \(Project.source!.masked) for changes")
    }

    if let port = port {
      startServer(port: port)
      CLI.log("[serve] serving \(Project.target!.masked) at http://localhost:\(port)")
    }

    if watch == true || port != nil {
      CLI.log("^c to stop")
      RunLoop.current.run()
    }
  }

  static func log(_ message: String) { print(message, to: &FileHandle.stderr) }

  func startServer(port: UInt16) {
    Server(path: Project.target!.masked, port: port) { (req, res, err) in
      var message: [String] = ["[serve]"]
      if let req { message.append(req.path) }
      if let res { message.append("(\(res.status.rawValue) \(res.status))") }
      if let err { message.append("Error: \(err)") }
      CLI.log(message.joined(separator: " "))
    }
  }

  func startWatcher() {
    Watcher(directory: Project.source!) { diff in
      guard !diff
        .map({ $0.url })
        .filter({
          guard Project.sourceContainsTarget else { return true }
          return !$0.absoluteString.contains(Project.target!.absoluteString) })
        .isEmpty
      else { return }
      Project.build()
    }
  }
}
