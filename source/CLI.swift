import ArgumentParser
import Foundation

@main
struct Alternator: ParsableCommand {
  static let configuration = CommandConfiguration(version: "2.2.0")

  @Argument(help: "Path to your source directory.", completion: .directory)
  var source: String
  @Argument(help: "Path to your target directory.", completion: .directory)
  var target: String
  @Flag(name: .shortAndLong, help: "Rebiuld <source> as you save changes.")
  var watch = false
  @Option(name: .shortAndLong, help: "Serve <target> on localhost:<port>.")
  var port: UInt16?

  func validate() throws {
    Project.source = URL(fileURLWithPath: source)
    Project.target = URL(fileURLWithPath: target)

    guard Project.source.exists else
      { throw ValidationError("<source> does not exist.") }
    guard Project.source.isDirectory else
      { throw ValidationError("<source> must be a directory.") }
    guard Project.source.path() != Project.target.path() else
      { throw ValidationError("<source> and <target> cannot be the same.") }
    guard !Project.target.exists || Project.target.isDirectory else
      { throw ValidationError("<target> must be a directory.") }
  }

  mutating func run() throws {
    Project.build()
    if watch { Project.watch() }
    if let port = port { Project.serve(port: port) }
    if watch || port != nil {
      print("^c to stop")
      RunLoop.current.run()
    }
  }
}
