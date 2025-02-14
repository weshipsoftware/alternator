import ArgumentParser
import Foundation
import FSDiffStream

@main
struct CLI: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "alternator", version: "2.0.0")

  @Argument(help:"Path to your source directory.", completion: .directory)
  var source: String

  @Argument(help:"Path to your target directory.", completion: .directory)
  var target: String

  @Option(name:.shortAndLong, help:"Port for the localhost server.")
  var port: UInt16?

  func validate() throws {
    Project.source = URL(string:source.asRef, relativeTo:URL.currentDirectory())
    guard Project.source!.exists else
      {throw ValidationError("<source> does not exist.")}
    guard Project.source!.isDirectory else
      {throw ValidationError("<source> must be a directory.")}

    Project.target = URL(string:target.asRef, relativeTo:URL.currentDirectory())
    guard Project.source!.masked != Project.target!.masked else
      {throw ValidationError("<source> and <target> cannot be the same directory.")}
    guard !Project.target!.exists || Project.target!.isDirectory else
      {throw ValidationError("<target> must be a directory.")}
  }

  mutating func run() throws {
    Project.build()
    if let port = port {
      watch()
      serve(port)
      print("^c to stop", to:&FileHandle.stderr)
      RunLoop.current.run()
    }
  }

  func watch() {
    FSDiffStream(Project.source!) { diff in
      guard !diff
        .map({ $0.url })
        .filter({guard Project.sourceContainsTarget else {return true}
          return !$0.absoluteString.contains(Project.target!.absoluteString)})
        .isEmpty
      else {return}
      Project.build()
    }
    print("[watch] watching \(Project.source!.masked) for changes", to:&FileHandle.stderr)
  }

  func serve(_ port: UInt16) {
    Server(path:Project.target!.masked, port:port) {(request, response, error) in
      var message:[String] = ["[serve]"]
      if let request  {message.append(request.path)}
      if let response {message.append("(\(response.status.rawValue) \(response.status))")}
      if let error    {message.append("Error: \(error)")}
      print(message.joined(separator:" "), to:&FileHandle.stderr)
    }
    print("[serve] serving \(Project.target!.masked) on http://localhost:\(port)",
      to:&FileHandle.stderr)
  }
}

extension FileHandle: @retroactive TextOutputStream {
  nonisolated(unsafe) static var stderr = FileHandle.standardError

  public func write(_ message: String)
    {write(message.data(using:.utf8)!)}
}
