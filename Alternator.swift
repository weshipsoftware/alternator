import ArgumentParser
import Foundation
import Ink
import Network
import RegexBuilder
import UniformTypeIdentifiers

@main
struct CLI: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "alternator", version: "1.0.0")

  @Argument(help: "Path to your source directory.", completion: .directory)
  var source: String
  @Argument(help: "Path to your target directory.", completion: .directory)
  var target: String
  @Flag(name: .shortAndLong, help: "Rebuild <source> as you save changes.")
  var watch = false
  @Option(name: .shortAndLong, help: "Serve <target> on localhost:<port>")
  var port: UInt16?

  func validate() throws {
    Project.source = URL(filePath: source, directoryHint: .isDirectory)
    Project.target = URL(filePath: target, directoryHint: .isDirectory)
    guard Project.source.exists
     else { throw ValidationError("<source> does not exist.") }
    guard Project.source.isDirectory
     else { throw ValidationError("<source> must be a directory.") }
    guard Project.source.standardizedFileURL != Project.target.standardizedFileURL
     else { throw ValidationError("<source> and <target> cannot be the same.") }
    guard !Project.target.exists || Project.target.isDirectory
     else { throw ValidationError("<target> must be a directory.")
    }
  }

  mutating func run() {
    Project.build()
    if watch {
      Watcher.run()
      print("[watch] watching \(source) for changes") }
    if let port = port {
      Server.run(port: port)
      print("[serve] serving \(target) on http://localhost:\(port)") }
    if watch || port != nil {
      print("^C to stop")
      RunLoop.current.run() }
  }
}

struct Project {
  nonisolated(unsafe) static var source, target: URL!

  static var manifest: [File] {
    FileManager.default
      .subpaths(atPath: source.path(percentEncoded: false))!
      .map { URL(filePath: $0, relativeTo: source) }
      .filter { !$0.isDirectory }
      .filter { !source.encloses(target) || !target.encloses($0) }
      .filter { !$0.isIgnored(relativeTo: source) }
      .map(File.init(source:))
  }

  static var derivedData: [URL] {
    FileManager.default
      .subpaths(atPath: target.path(percentEncoded: false))!
      .map { URL(filePath: $0, relativeTo: target) }
      .filter { !$0.isIgnored(relativeTo: target) }
      .filter { (!target.encloses(source) || !source.encloses($0)) }
  }

  static func build() {
    do {
      try manifest.forEach { try $0.build() }
      try derivedData.filter({ $0.isOrphaned }).forEach(prune)
      try derivedData
        .filter { $0.isDirectory }
        .filter { try $0.isEmpty }
        .forEach(prune)
    } catch { print("[error]", error) }
  }

  static func find(_ path: String) -> File? {
    let url = URL(filePath: path, relativeTo: source)
    guard url.exists else { return nil }
    return File(source: url)
  }

  static func prune(at url: URL) throws {
    print("[build] deleting", "\(target.relativePath)/\(url.relativePath)")
    try FileManager.default.removeItem(at: url)
  }
}

struct File {
  var source: URL

  var target: URL {
    let url = URL(filePath: source.relativePath, relativeTo: Project.target)
    return url.isType(.markdown)
    ? url.deletingPathExtension().appendingPathExtension("html") : url
  }

  var isRenderable: Bool {
    guard source.pathExtension != "" else { return false }
    return UTType(filenameExtension: source.pathExtension)!.conforms(to: UTType.text)
  }

  var isModified: Bool { get throws {
    guard
      target.exists,
      let sourceModDate = try source.modificationDate,
      let targetModDate = try target.modificationDate,
      targetModDate > sourceModDate
    else { return true }
    return try dependencies.contains
     { try $0.source.modificationDate! > targetModDate }
  }}

  var dependencies: [Self] { get throws {
    guard isRenderable else { return [] }
    let files: [File?] = try contents
      .comments(Include.pattern)
      .map {Include(fragment: $0).parse?.0}
    + [try source.template]
    return try files
      .filter { $0 != nil && $0!.source.exists == true }
      .flatMap { try [$0!] + $0!.dependencies }
      .map { $0.source }
      .reduce(into: Set<URL>(), { (ary, file) in ary.insert(file) })
      .map { Self(source: $0) }
  }}

  var contents: String { get throws {
    let text = try source.asString
    if source.isType(.markdown) { return MarkdownParser.shared.html(from: text) }
    guard
      try !source.metadata.isEmpty,
      let match = text.firstMatch(of: Regex {
        Anchor.startOfSubject; "---"
        ZeroOrMore(.any, .reluctant)
        "---"; Anchor.endOfLine
      })?.output.description
    else { return text }
    return text.replacingFirst(of: match)
  }}

  func build() throws {
    guard try isModified
      && !source.isDirectory
      && !source.isIgnored(relativeTo: Project.source)
    else { return }
    if target.exists { try FileManager.default.removeItem(at: target) }
    try FileManager.default.createDirectory(
      atPath: target.deletingLastPathComponent().path(percentEncoded: false),
      withIntermediateDirectories: true)
    if isRenderable {
      print("[build] rendering",
        "\(Project.source.relativePath)/\(source.relativePath) →",
        "\(Project.target.relativePath)/\(target.relativePath)")
      FileManager.default.createFile(
        atPath: target.path(percentEncoded: false),
        contents: try render().data(using: .utf8))
    } else {
      print("[build] copying",
        "\(Project.source.relativePath)/\(source.relativePath) →",
        "\(Project.target.relativePath)/\(target.relativePath)")
      try source.touch()
      try FileManager.default.copyItem(at: source, to: target)
      try target.touch()
    }
  }

  func render(_ context: [String:String] = [:]) throws -> String {
    var text = try contents
    var context = context.merging(try source.metadata, uniquingKeysWith: { (x, _) in x })
    if context["@layout"] == "false" { context.removeValue(forKey: "@layout") }
    if let layout = context["@layout"], let template = Project.find(layout) {
      (text, context) = try Layout(context: context, template: template)
        .render(text) }
    context.removeValue(forKey: "@layout")
    for fragment in text.comments(Include.pattern) {
      text = text.replacingFirst(of: fragment, with: try Include(fragment: fragment)
        .render(context)) }
    for fragment in text.comments(Variable.pattern) {
      text = text.replacingFirst(of: fragment, with: Variable(fragment: fragment)
        .render(context)) }
    return text
  }
}

struct Layout {
  let context: [String: String], template: File

  nonisolated(unsafe) private static var pattern = Regex
   { ZeroOrMore(.whitespace); "@content"; ZeroOrMore(.whitespace) }

  func render(_ content: String) throws -> (String, [String: String]) {
    var text = try template.contents
    for match in text.comments(Self.pattern) {
      text = text.replacingOccurrences(of: match, with: content) }
    var context = context.merging(try template.source.metadata,
      uniquingKeysWith: { (x, _) in x })
    if let template = try template.source.template {
      (text, context) = try Layout(context: context, template: template).render(text) }
    return (text, context)
  }
}

struct Include {
  let fragment: String

  nonisolated(unsafe) static let pattern = Regex
   { ZeroOrMore(.whitespace); "@include"; ZeroOrMore(.any, .reluctant) }

  var parse: (File, [String: String])? {
    guard let comment = fragment.comment?.replacingFirst(of: "@include")
     else { return nil }
    let pattern = Regex
     { OneOrMore(.whitespace); "@"; OneOrMore(.any, .reluctant); ":" }
    let parts = comment
      .split(separator: pattern)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard
      parts.count > 0,
      let path = parts.first?.split(separator: "/").joined(separator: "/"),
      let file = Project.find(path),
      file.source.exists,
      file.isRenderable
     else { return nil }
    let keys: [String] = comment
      .matches(of: pattern)
      .map { comment[$0.range]
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .dropLast().description }
    let args: [String: String] = Dictionary(
      uniqueKeysWithValues: zip(keys, parts.dropFirst()))
    return (file, args)
  }

  func render(_ context: [String: String]) throws -> String {
    guard let (file, args) = parse else { return fragment }
    let context = context.merging(args, uniquingKeysWith: { (_, x) in x })
    return try file.render(context)
  }
}

struct Variable {
  var fragment: String

  nonisolated(unsafe) static let pattern = Regex
   { ZeroOrMore(.whitespace); "@"; OneOrMore(.any, .reluctant) }

  func render(_ context: [String: String]) -> String {
    guard let comment = fragment.comment else { return fragment }
    let parts = comment
      .split(separator: "??", maxSplits: 1)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard
      parts.first?.split(separator: " ").count == 1,
      let key = parts.first
    else { return fragment }

    return context[key] != nil ? context[key]! : parts.count == 2 ? parts.last! : fragment
  }
}

struct Watcher {
  static func run() {
    let stream: FSEventStreamRef = FSEventStreamCreate(
      nil, onChange, nil,
      [Project.source.path(percentEncoded: false) as NSString] as NSArray,
      UInt64(kFSEventStreamEventIdSinceNow), 1.0,
      FSEventStreamEventFlags(kFSEventStreamCreateFlagFileEvents))!
    FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
    FSEventStreamStart(stream)
  }

  static let onChange: FSEventStreamCallback = { (_, _, count, paths, _, _) in
    let start    = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
    let pointers = UnsafeBufferPointer(start: start, count: count)
    let changes  = (0..<count)
      .map { URL(
        fileURLWithFileSystemRepresentation: pointers[$0],
        isDirectory: false,
        relativeTo: nil) }
      .reduce(into: Set<URL>(), { (result, x) in result.insert(x) })
      .filter(isWatchable)
    guard !changes.isEmpty else { return }
    Project.build()

    func isWatchable(url:URL) -> Bool {
      guard url.lastPathComponent != ".DS_Store"    else { return false }
      guard Project.source.encloses(Project.target) else { return true  }
      return !Project.target.encloses(url)
    }
  }
}

struct Server {
  static func run(port: UInt16) {
    let listener = try! NWListener(using: .tcp, on: NWEndpoint.Port(rawValue:port)!)
    listener.newConnectionHandler = { (_ conn) in
      conn.start(queue: .main)
      Server.receive(from: conn) }
    listener.start(queue: .main)
  }

  static func receive(from conn: NWConnection) {
    conn.receive(minimumIncompleteLength: 1, maximumLength: conn.maximumDatagramSize)
    { data, _, complete, error in
			if let error { print("[serve] Error:", error.localizedDescription) }
			else if let data, let req = Request(data) { respond(on:conn, req:req) }
			if !complete { receive(from: conn) }
		}
  }

  static func respond(on conn: NWConnection, req: Request) {
    let refs = [req.path,
      "\(req.path)/index.html", "\(req.path)/index.htm",
      "\(req.path).html",       "\(req.path).htm"
    ].map { $0.split(separator: "/").joined(separator: "/") }
    guard
      let found = refs.first(where: {
        let file = URL(filePath: $0, relativeTo: Project.target)
        return file.exists && !file.isDirectory }),
      let res = try? Response(at: URL(filePath: found, relativeTo: Project.target))
    else {
      let res = Response(.notFound, contentType: req.contentType)
      print("[serve] \(req.path) (\(res.status.rawValue) \(res.status))")
      conn.send(content: res.data, completion: .idempotent)
      return
    }

    print("[serve] \(req.path) (\(res.status.rawValue) \(res.status)")
    conn.send(content: res.data, completion: .idempotent)
  }
}

struct Request {
  let path: String

  var contentType: UTType {
    let ext = URL(string: path)!.pathExtension
    return ext == "" || ["html", "htm"].contains(ext) ? .html : .plainText
  }

  init?(_ data: Data) {
    let req = String(data: data, encoding: .utf8)!.components(separatedBy: "\r\n")
    guard let line = req.first, req.last!.isEmpty else { return nil }
    let components = line.components(separatedBy: " ")
    guard components.count == 3 else { return nil }
    self.path = components[1]
  }
}

struct Response {
  let body: Data, status: Status, headers: [Header: String]
  
  enum Status: Int, CustomStringConvertible {
    case ok = 200, notFound = 404
    var description: String { switch self {
      case .ok:       "OK"
      case .notFound: "Not Found"
    }}
  }

  enum Header: String { case contentLength = "Content-Length", contentType = "Content-Type" }

  var data: Data {
    var lines = ["HTTP/1.1 \(status.rawValue) \(status)"]
    lines.append(contentsOf: headers.map { "\($0.key.rawValue): \($0.value)" })
    lines.append(""); lines.append("")
    return lines.joined(separator: "\r\n").data(using: .utf8)! + body
  }

  init(_ status: Status  = .ok,    body: Data = Data(),
    contentType: UTType? = nil, headers: [Header: String] = [:])
  {
    self.status = status
    let notFoundFile = URL(filePath: "404.html", relativeTo: Project.target)
    self.body = status == .notFound && contentType == .html && notFoundFile.exists
    ? try! Data(contentsOf: notFoundFile) : body
    self.headers = headers.merging(
      [.contentLength: String(self.body.count),
       .contentType: contentType?.preferredMIMEType
      ].compactMapValues { $0 }, uniquingKeysWith: { _, x in x })
  }

  init(at url: URL) throws
   { self.init(body: try Data(contentsOf: url), contentType: try url.contentType) }
}

extension MarkdownParser { nonisolated(unsafe) static let shared = Self() }

extension String {
  var comment: Self? {
    let pattern = Capture { ZeroOrMore(.any, .reluctant) }
    let regex = ChoiceOf {
      Regex { "<!--"; pattern; "-->"            }
      Regex { "//";   pattern; Anchor.endOfLine }
      Regex { "/*";   pattern; "*/"             } }
    guard
      let matches = firstMatch(of: regex),
      let match = [matches.1, matches.2, matches.3].first(where: { $0 != nil })
    else { return nil }
    return match!.description.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func comments(_ pattern: Regex<Substring> = Regex { ZeroOrMore(.any, .reluctant) })
  -> [String] {
    matches(of: ChoiceOf {
      Regex { "<!--"; pattern; "-->"            }
      Regex { "//";   pattern; Anchor.endOfLine }
      Regex { "/*";   pattern; "*/"             }
    }).map {self[$0.range].description}
  }

  func replacingFirst(of: Self, with: Self = "") -> Self {
    guard let range = range(of: of) else { return self }
    return replacingCharacters(in: range, with: with)
  }
}

extension URL {
  enum Exception: Error, CustomStringConvertible {
    case resourceDoesNotExist, resourceIsADirectory, resourceIsNotADirectory
    var description: String { switch self {
      case .resourceDoesNotExist:    "Resource does not exist."
      case .resourceIsADirectory:    "Resource is a directory."
      case .resourceIsNotADirectory: "Resource is not a directory."
    }}
  }

  var asString: String { get throws {
    guard exists       else { throw Exception.resourceDoesNotExist }
    guard !isDirectory else { throw Exception.resourceIsADirectory }
    return String(decoding: try Data(contentsOf: self), as: UTF8.self)
  }}

  var contentType: UTType? { get throws
   { try resourceValues(forKeys: [.contentTypeKey]).contentType }}

  var decodedPath: String { standardizedFileURL.path(percentEncoded: false) }

  func encloses(_ url: URL) -> Bool {
    guard isDirectory else { return false }
    let sup = standardizedFileURL.pathComponents
    let sub = url.standardizedFileURL.pathComponents
    return sup.count < sub.count && !zip(sup, sub).contains(where: !=)
  }

  var exists: Bool { FileManager.default.fileExists(atPath: decodedPath) }

  var isDirectory: Bool {
    guard exists else { return false }
    var isDir:ObjCBool = false
    FileManager.default.fileExists(atPath: decodedPath, isDirectory: &isDir)
    return isDir.boolValue
  }

  var isEmpty: Bool { get throws {
    guard exists      else { throw Exception.resourceDoesNotExist    }
    guard isDirectory else { throw Exception.resourceIsNotADirectory }
    return try FileManager.default.contentsOfDirectory(atPath: decodedPath).isEmpty
  }}

  func isIgnored(relativeTo: URL = URL(filePath: "/")) -> Bool {
    var components = standardizedFileURL.pathComponents
    if relativeTo.encloses(self) {
      components = components
        .dropFirst(relativeTo.standardizedFileURL.pathComponents.count)
        .map { String($0) } }
    return components.contains(where: { $0.first == "." })
  }
  
  var isOrphaned: Bool {
    guard exists && !isDirectory else { return false }
    return !Project.manifest.map({ $0.target.relativePath }).contains(relativePath)
  }

  func isType(_ type: UTType) -> Bool {
    guard pathExtension.count > 0 else { return type == .directory }
    return UTType(filenameExtension:pathExtension)!.conforms(to:type)
  }

  var metadata: [String: String] { get throws {
    guard exists else { throw Exception.resourceDoesNotExist }
    return MarkdownParser.shared.parse(try asString).metadata
  }}

  var modificationDate: Date? { get throws {
    guard exists else { throw Exception.resourceDoesNotExist }
    return try FileManager.default
      .attributesOfItem(atPath:decodedPath)[.modificationDate] as? Date
  }}

  var template: File? { get throws {
    guard let path = try metadata["@layout"] else { return nil }
    return Project.find(path)
  }}

  func touch() throws {
    var (file, resourceValues) = (self, URLResourceValues())
    resourceValues.contentModificationDate = Date.now
    try file.setResourceValues(resourceValues)
  }
}

extension UTType {
  static var markdown: UTType
   { Self(exportedAs: "net.daringfireball.markdown", conformingTo: .plainText) }
}