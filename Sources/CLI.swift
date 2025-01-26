import ArgumentParser
import Foundation

@main
struct CLI: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "alternator", version: "2.0.0")

  @Argument(help:"Path to your source directory.")
  var source: String = "."

  @Argument(help:"Path to your target directory.")
  var target: String = "<source>/_build"

  @Option(name:.shortAndLong, help:"Port for the localhost server.")
  var port: UInt16?

  mutating func run() throws {
    if target == "<source>/_build" {target = "\(source)/_build"}

    Project.source = URL(string:source.asRef, relativeTo:URL.currentDirectory())
    Project.target = URL(string:target.asRef, relativeTo:URL.currentDirectory())

    guard Project.source!.exists else
      {throw ValidationError("<source> does not exist.")}

    guard Project.source!.masked != Project.target!.masked else
      {throw ValidationError("<source> and <target> cannot be the same directory.")}

    Project.build()

    if let port = port {
      Project.source!.watch() {urls in
        guard !urls
          .filter({guard Project.sourceContainsTarget else {return true}
            return !$0.absoluteString.contains(Project.target!.absoluteString)})
          .isEmpty
        else {return}
        Project.build()
      }

      print("[watch] watching \(Project.source!.masked) for changes", to:&FileHandle.stderr)

      Project.target!.serve(port:port) {(request, response, error) in
        var message:[String] = ["[serve]"]
        if let request  {message.append(request.path)}
        if let response {message.append("(\(response.status.rawValue) \(response.status))")}
        if let error    {message.append("Error: \(error)")}
        print(message.joined(separator:" "), to:&FileHandle.stderr)
      }

      print("[serve] serving \(Project.target!.masked) on http://localhost:\(port)",
        to:&FileHandle.stderr)

      print("^c to stop", to:&FileHandle.stderr)
      RunLoop.current.run()
    }
  }
}

extension FileHandle: @retroactive TextOutputStream {
  nonisolated(unsafe) static var stderr = FileHandle.standardError

  public func write(_ message: String)
    {write(message.data(using:.utf8)!)}
}