import ArgumentParser
import Foundation

@main
struct Alternator: ParsableCommand {
  static let configuration = CommandConfiguration(version: "2.1.0")

  @Argument(help: "Path to your source directory.", completion: .directory)
  var source: String

  @Argument(help: "Path to your target directory.", completion: .directory)
  var target: String

  @Flag(name: .shortAndLong, help: "Rebuild <source> as you save changes.")
  var watch = false

  @Option(name: .shortAndLong, help: "Serve <target> on localhost:<port>.")
  var port: UInt16?

  mutating func run() throws {
    Project.build()

    if watch   == true {FSDiffStream()}
    if let port = port {HTTPServer(port: port)}

    if watch == true || port != nil {
      echo("^c to stop")
      RunLoop.current.run()
    }
  }

  func validate() throws {
    Project.src = URL(string: source.ref, relativeTo: URL.currentDirectory())
    Project.tgt = URL(string: target.ref, relativeTo: URL.currentDirectory())

    guard Project.src!.exists
    else {throw ValidationError("<source> does not exist.")}

    guard Project.src!.isDirectory
    else {throw ValidationError("<source> must be a directory.")}

    guard Project.src!.masked != Project.tgt!.masked
    else {throw ValidationError("<source> and <target> cannot be the same.")}

    guard !Project.tgt!.exists || Project.tgt!.isDirectory
    else {throw ValidationError("<target> must be a directory.")}
  }
}