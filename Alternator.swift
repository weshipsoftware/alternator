import ArgumentParser
import Foundation
import Ink
import FSDiffStream
import Prettier
import PrettierBabel
import PrettierHTML
import PrettierPostCSS
import RESTless

@main
struct CLI: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "alternator", version: "2.0.0")

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

    guard Project.source!.exists else
      {throw ValidationError("<source> does not exist.")}

    guard Project.source!.isDirectory else
      {throw ValidationError("<source> must be a directory.")}

    guard Project.source!.masked != Project.target!.masked else
      {throw ValidationError("<source> and <target> cannot be the same directory.")}

    guard !Project.target!.exists || Project.target!.isDirectory else
      {throw ValidationError("<target> must be a directory.")}
  }

  mutating func run() throws {
    Project.build()

    if watch == true
      {Project.stream()}

    if let port = port
      {Project.serve(port: port)}

    if watch == true || port != nil {
      CLI.log("^c to stop")
      RunLoop.current.run()
    }
  }

  static func log(_ message: String)
    {print(message, to: &FileHandle.stderr)}
}

struct Project {
  nonisolated(unsafe) static var source: URL?
  nonisolated(unsafe) static var target: URL?

  static var sourceContainsTarget: Bool {target!.masked.contains(source!.masked)}
  static var targetContainsSource: Bool {source!.masked.contains(target!.masked)}

  static func build() {
    do {
      let manifest = source!
        .list
        .filter {!$0.isDirectory}
        .filter {
          !sourceContainsTarget
          ? true
          : !$0.absoluteString.contains(target!.absoluteString)}
        .map {File(source: $0)}

      try manifest
        .filter {$0.source.lastPathComponent.prefix(1) != "!"}
        .filter {try $0.isModified}
        .forEach {try $0.build()}

      try target!.list
        .filter {!$0.isDirectory}
        .filter {!manifest.map({$0.source.absoluteString}).contains($0.absoluteString)}
        .filter {!manifest.map({$0.target.absoluteString}).contains($0.absoluteString)}
        .forEach {
          CLI.log("[build] deleting \($0.masked)")
          try FileManager.default.removeItem(at:$0)}

      try target!.list
        .filter {$0.isDirectory}
        .filter {
          !targetContainsSource
          ? true
          : !$0.absoluteString.contains(source!.absoluteString)}
        .filter {try FileManager.default
          .contentsOfDirectory(atPath: $0.path(percentEncoded: false))
          .isEmpty}
        .forEach {
          CLI.log("[build] deleting \($0.masked)")
          try FileManager.default.removeItem(at: $0)}
    }

    catch {
      guard ["no such file", "doesn’t exist", "already exists", "couldn’t be removed."]
        .contains(where: error.localizedDescription.contains)
      else {
        CLI.log("[build] Error: \(error.localizedDescription)")
        exit(1)
      }
    }
  }

  static func file(_ ref: String) -> File? {
    source!
      .list
      .filter {!$0.isDirectory}
      .map {File(source: $0)}
      .first(where: {$0.ref == ref})
  }

  static func serve(port: UInt16) {
    RESTless(path: target!.masked, port: port) {(req, res, err) in
      var message: [String] = ["[serve]"]
      if let req {message.append(req.path)}
      if let res {message.append("(\(res.status.rawValue) \(res.status))")}
      if let err {message.append("Error: \(err)")}
      CLI.log(message.joined(separator: " "))
    }

    CLI.log("[serve] serving \(target!.masked) at http://localhost:\(port)")
  }

  static func stream() {
    FSDiffStream(source!) { diff in
      guard !diff
        .map({$0.url})
        .filter({
          guard sourceContainsTarget else {return true}
          return !$0.absoluteString.contains(target!.absoluteString)})
        .isEmpty
      else {return}
      build()
    }

    CLI.log("[watch] watching \(source!.masked) for changes")
  }
}

struct File {
  let source: URL

  var contents: String {
    get throws {
      let text = try source.contents

      if source.pathExtension == "md" {
        let parsedText = MarkdownParser.shared.html(from: text)
        switch PrettierFormatter.shared.format(parsedText) {
          case .success(let formattedText):
            return formattedText
          case .failure(let error):
            CLI.log("[build] Warning: \(error)")
            return parsedText
        }
      }

      if try metadata.isEmpty == true
        {return text}

      if let match = text.find(#"---(\n|.)*?---\n"#).first
        {return text.replacingFirst(of:match)}

      return text
    }
  }

  var dependencies: [File] {
    get throws {
      guard isRenderable else {return []}

      let deps: [File?] = try contents
        .find(Include.pattern)
        .map {Include(fragment: $0).file}
        + [try layout]

      return try deps
        .filter {$0 != nil && $0!.source.exists == true}
        .map {$0!}
        .flatMap {try [$0] + $0.dependencies}
        .map {$0.source}
        .unique
        .map {File(source: $0)}
    }
  }

  var isModified: Bool {
    get throws {
      guard target.exists,
        let sourceModDate = try source.modificationDate,
        let targetModDate = try target.modificationDate,
        targetModDate > sourceModDate
      else {return true}

      return try dependencies.contains
        {try $0.source.modificationDate! > targetModDate}
    }
  }

  var isRenderable: Bool {
    ["css", "htm", "html", "js", "md", "rss", "svg", "txt", "xml"]
      .contains(source.pathExtension)
  }

  var layout: File? {
    get throws {
      guard let ref = try metadata["#layout"] else {return nil}
      return Project.file(ref)
    }
  }

  var metadata: [String: String] {
    get throws
      {MarkdownParser.shared.parse(try source.contents).metadata}
  }

  var ref: String {
    source
      .path(percentEncoded: false)
      .replacingFirst(of: Project.source!.path())
      .asRef
  }

  var target: URL {
    let url = Project.target!.appending(path: ref)
    return url.pathExtension == "md"
    ? url.deletingPathExtension().appendingPathExtension("html")
    : url
  }

  func build() throws {
    if target.exists
      {try FileManager.default.removeItem(at: target)}

    try FileManager.default.createDirectory(
      atPath: target.deletingLastPathComponent().path(percentEncoded: false),
      withIntermediateDirectories: true)

    if isRenderable {
      CLI.log("[build] rendering \(source.masked) -> \(target.masked)")
      FileManager.default.createFile(
        atPath: target.path(percentEncoded: false),
        contents: try render().data(using: .utf8))
    }

    else {
      CLI.log("[build] copying \(source.masked) -> \(target.masked)")
      try source.touch()
      try FileManager.default.copyItem(at: source, to: target)
      try target.touch()
    }
  }

  func render(_ context: [String: String] = [:]) throws -> String {
    var context = context.merging(try metadata, uniquingKeysWith: {(x, _) in x})
    var text    = try contents

    if let layout = try layout {
      let macro = Layout(content: text, template: layout)
      context = context.merging(try macro.template.metadata, uniquingKeysWith: {(x, _) in x})
      text = try macro.render()
    }

    for match in text.find(Include.pattern) {
      let macro = Include(fragment: match)
      if macro.file?.source.exists == true {
        var params = macro.parameters
        for (key, val) in params where context[val] != nil
          {params[key] = context[val]}
        text = text.replacingFirst(of: match, with: try macro.file!.render(params))
      }
    }

    for match in text.find(Variable.pattern) {
      let macro = Variable(fragment: match)
      if let value = context.contains(where: {$0.key == macro.key})
      ? context[macro.key]
      : macro.defaultValue
        {text = text.replacingFirst(of: match, with: value as String)}
    }

    return text
  }
}

struct Layout {
  let content:  String
  let template: File

  static let pattern =
    #"((<!--|/\*|/\*\*)\s*#content[\s\S]*?(-->|\*/)|//[^\S\r\n]*#content[^\n]*)"#

  func render() throws -> String {
    var text = try template.contents
    for match in text.find(Layout.pattern)
      {text = text.replacingFirst(of: match, with: content)}
    if let ref = try template.metadata["#layout"], let file = Project.file(ref)
      {text = try Layout(content: text, template: file).render()}
    return text
  }
}

struct Include {
  var fragment: String

  static let pattern =
    #"((<!--|/\*|/\*\*)\s*#include[\s\S]*?(-->|\*/)|//[^\S\r\n]*#include[^\n]*)"#

  var arguments:String? {
    enum Predicate: String {
      case singleLine = #"//\s*#include\s+(?<args>.+?)"#
      case multiLine  = #"(<!--|/\*|/\*\*)\s*#include\s+(?<args>(.|\n)+?)(-->|\*/)"#
    }

    if let match = try? Regex(Predicate.singleLine.rawValue).wholeMatch(in: fragment)
      {return match["args"]?.substring?.description}
    if let match = try? Regex(Predicate.multiLine.rawValue).wholeMatch(in: fragment)
      {return match["args"]?.substring?.description}

    return nil
  }

  var file: File? {
    guard let ref = arguments?
      .split(separator: " ")
      .first?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    else {return nil}

    return Project.file(ref)
  }

  var parameters: [String: String] {
    var params: [String: String] = [:]

    guard let args = arguments?
      .split(separator: " ")
      .dropFirst()
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    else {return params}

    let keys = args.find(#"(@\S+:|#\S+:)"#)
      .map {$0.dropLast().description}
    let vals = args.split(separator: /(@\S+:|#\S+:)/)
      .map {$0.trimmingCharacters(in: .whitespacesAndNewlines)}

    for (k, v) in zip(keys, vals) {params[k] = v.description}

    return params
  }
}

struct Variable {
  var fragment: String

  static let pattern =
    #"((<!--|/\*|/\*\*)\s*@[\s\S]*?(-->|\*/)|//[^\S\r\n]*@[^\n]*)"#

  var arguments: [String] {
    enum Predicate: String {
      case singleLine = #"//\s*@+(?<var>.+?)"#
      case multiLine  = #"(<!--|/\*|/\*\*)\s*@(?<var>(.|\n)+?)(-->|\*/)"#
    }

    var args = ""
    if let match = try? Regex(Predicate.singleLine.rawValue).wholeMatch(in: fragment)
      {args = match["var"]!.substring!.description}
    if let match = try? Regex(Predicate.multiLine.rawValue).wholeMatch(in: fragment)
      {args = match["var"]!.substring!.description}

    return args
      .split(separator: "??", maxSplits: 1)
      .map {$0.trimmingCharacters(in: .whitespacesAndNewlines)}
      .enumerated()
      .map {(i, arg) in i == 0 ? "@" + arg : arg}
  }

  var defaultValue: String?
    {arguments.count == 2 ? arguments.last : nil}

  var key: String
    {arguments.first!}
}

extension Array where Element: Hashable {
  var unique: [Element]
    {Array(Set(self))}
}

extension FileHandle: @retroactive TextOutputStream {
  nonisolated(unsafe) static var stderr = FileHandle.standardError

  public func write(_ message: String)
    {write(message.data(using: .utf8)!)}
}

extension MarkdownParser {
  nonisolated(unsafe) static let shared = MarkdownParser()
}

extension PrettierFormatter {
  static var shared: PrettierFormatter {
    let formatter = PrettierFormatter(
      plugins: [HTMLPlugin(), PostCSSPlugin(), BabelPlugin()],
      parser: HTMLParser())
    formatter.prepare()
    return formatter
  }
}

extension String {
  var asRef: String
    {split(separator: "/").joined(separator: "/")}

  func find(_ pattern: String) -> [String] {
    try! NSRegularExpression(pattern: pattern)
      .matches(in: self, range: NSRange(location: 0, length: self.utf16.count))
      .map {(self as NSString).substring(with: $0.range)}
  }

  func replacingFirst(of: String, with: String = "") -> String {
    guard let range = range(of: of) else {return self}
    return replacingCharacters(in: range, with: with)
  }
}

extension URL {
  var contents: String {
    get throws
      {String(decoding: try Data(contentsOf: self), as: UTF8.self)}
  }

  var exists: Bool
    {FileManager.default.fileExists(atPath: path(percentEncoded: false))}

  var isDirectory: Bool
    {(try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true}

  var list: [URL] {
    guard exists else {return []}
    return FileManager.default
      .subpaths(atPath: path())!
      .filter {
        !$0
          .split(separator: "/")
          .contains(where: {component in component.first == "."})}
      .map {appending(component: $0)}
  }

  var masked: String {
    path(percentEncoded: false)
      .replacingFirst(of: FileManager.default.currentDirectoryPath)
      .replacingFirst(of: "file:///")
      .asRef
  }

  var modificationDate: Date? {
    get throws {
      let (file, key) = (path(percentEncoded: false), FileAttributeKey.modificationDate)
      return try FileManager.default.attributesOfItem(atPath: file)[key] as? Date
    }
  }

  func touch() throws {
    var (file, resourceValues) = (self, URLResourceValues())
    resourceValues.contentModificationDate = Date.now
    try file.setResourceValues(resourceValues)
  }
}
