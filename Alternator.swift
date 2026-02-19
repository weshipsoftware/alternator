// Note for future me:
//   Yes, this is tightly coupled in a few spots.
//   It’s only one file and it does not need to be reused. It’s fine.
//   Also, decoupling FSEventStream is a pain in the ass.

import ArgumentParser
import Foundation
import Ink
import Network
import RegexBuilder
import UniformTypeIdentifiers

/**
 Command line interface.
 */
@main
struct Alternator: ParsableCommand {
  /**
   Defines the release version.
   */
  static let configuration = CommandConfiguration(version: "1.0.0")

  @Argument(help: "Path to your source directory.", completion: .directory)
  var source: String

  @Argument(help: "Path to your target directory.", completion: .directory)
  var target: String

  @Flag(name: .shortAndLong, help: "Rebuild <source> as you save changes.")
  var watch = false

  @Option(name: .shortAndLong, help: "Serve <target> on localhost:<port>")
  var port: UInt16?

  /**
   Checks that the `source` and `target` user inputs are buildable directories.
   */
  func validate() throws {
    Project.source = URL(filePath: source, directoryHint: .isDirectory)
    Project.target = URL(filePath: target, directoryHint: .isDirectory)

    guard Project.source.exists else {
      throw ValidationError("<source> does not exist.")
    }

    guard Project.source.isDirectory else {
      throw ValidationError("<source> must be a directory.")
    }

    guard Project.source.standardizedFileURL != Project.target.standardizedFileURL else {
      throw ValidationError("<source> and <target> cannot be the same.")
    }

    guard !Project.target.exists || Project.target.isDirectory else {
      throw ValidationError("<target> must be a directory.")
    }
  }

  /**
   Runs the command.
   */
  mutating func run() {
    Project.build()

    if watch {
      Watcher.run()
      print("[watch] watching \(source) for changes")
    }

    if let port = port {
      Server.run(port: port)
      print("[serve] serving \(target) on http://localhost:\(port)")
    }

    if watch || port != nil {
      print("^C to stop")
      RunLoop.current.run()
    }
  }
}

/**
 Responsible for project configuration and building.
 */
struct Project {
  /**
   Location to build _from_.
   */
  nonisolated(unsafe) static var source: URL!

  /**
   Location to build _to_.
   */
  nonisolated(unsafe) static var target: URL!

  /**
   Builds the project.
   
   1. Builds each non—ignored resource from `source`.
   2. Removes all non–ignored resources from `target`
      that did not come from `source`.
   3. Removes all empty directories from `target`.
   */
  static func build() {
    do {
      try manifest.forEach { try $0.build() }
      try derivedData.filter(isOrphaned).forEach(prune)
      try derivedData
        .filter { $0.isDirectory }
        .filter { try $0.isEmpty }
        .forEach(prune)
    } catch { print("[error]", error) }
  }

  /**
  Returns a file from `source` based on a given relative path.
   */
  static func find(_ path: String) -> File? {
    let url = URL(filePath: path, relativeTo: source)
    guard url.exists else { return nil }
    return File(source: url)
  }

  /**
   List of `target` files built from `source`.
   */
  private static var derivedData: [URL] {
    FileManager.default
      .subpaths(atPath: target.path(percentEncoded: false))!
      .map { URL(filePath: $0, relativeTo: target) }
      .filter { !$0.isIgnored(relativeTo: target) }
      .filter { (!target.encloses(source) || !source.encloses($0)) }
  }

  /**
   Determines if a `target` file’s corresponding `source` file is missing.
   
   Orphaned files are to–be–deleted.
   */
  private static func isOrphaned(url: URL) -> Bool {
    guard url.exists && !url.isDirectory else { return false }
    return !manifest.map({ $0.target.relativePath }).contains(url.relativePath)
  }

  /**
   List if `source` files to be built.
   */
  private static var manifest: [File] {
    FileManager.default
      .subpaths(atPath: source.path(percentEncoded: false))!
      .map { URL(filePath: $0, relativeTo: source) }
      .filter { !$0.isDirectory }
      .filter { !source.encloses(target) || !target.encloses($0) }
      .filter { !$0.isIgnored(relativeTo: source) }
      .map(File.init(source:))
  }

  /**
   Removes a `target` file.
   */
  private static func prune(at url: URL) throws {
    print("[build] deleting", "\(Project.target.relativePath)/\(url.relativePath)")
    try FileManager.default.removeItem(at: url)
  }
}

/**
 Responsible for individual file configuration and building.
 */
struct File {
  /**
   Location to build _from_.
   */
  var source: URL

  /**
   Location to build _to_.
   */
  var target: URL {
    let url = URL(filePath: source.relativePath, relativeTo: Project.target)
    return url.isType(.markdown)
    ? url.deletingPathExtension().appendingPathExtension("html") : url
  }

  /**
   Determines if `source` should be rendered or copied to `target` as–is.
   */
  var isRenderable: Bool {
    guard source.pathExtension != "" else { return false }
    return UTType(filenameExtension: source.pathExtension)!.conforms(to: UTType.text)
  }

  /**
   Contents from `source` with the frontmatter removed.
   */
  var contents: String {
    get throws {
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
    }
  }

  /**
   Builds the file from `source` to `target`.
   
   Only builds new and/or modified files.
   */
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
    }

    else {
      print("[build] copying",
        "\(Project.source.relativePath)/\(source.relativePath) →",
        "\(Project.target.relativePath)/\(target.relativePath)")
      try source.touch()
      try FileManager.default.copyItem(at: source, to: target)
      try target.touch()
    }
  }

  /**
   Renders `contents`.
   
   1. Render the layout (if present).
   2. Render the includes.
   3. Render the variables.
   
   Nested rendering is recursive.
   */
  func render(_ context: [String:String] = [:]) throws -> String {
    var text = try contents
    var context = context.merging(try source.metadata, uniquingKeysWith: { (x, _) in x })
    
    if context["@layout"] == "false" { context.removeValue(forKey: "@layout") }

    if let layout = context["@layout"], let template = Project.find(layout) {
      (text, context) = try Layout(context: context, template: template)
        .render(text)
    }

    context.removeValue(forKey: "@layout")

    for fragment in text.comments(Include.pattern) {
      text = text.replacingFirst(of: fragment, with: try Include(fragment: fragment)
        .render(context))
    }

    for fragment in text.comments(Variable.pattern) {
      text = text.replacingFirst(of: fragment, with: Variable(fragment: fragment)
        .render(context))
    }

    return text
  }

  /**
   Recusrive list of files `source` uses as layouts and includes.
   */
  private var dependencies: [Self] {
    get throws {
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
    }
  }

  /**
   Determines if a `source` has been modified since `target` was last built.
   */
   private var isModified: Bool {
    get throws {
      guard
        target.exists,
        let sourceModDate = try source.modificationDate,
        let targetModDate = try target.modificationDate,
        targetModDate > sourceModDate
      else { return true }

      return try dependencies.contains {
        try $0.source.modificationDate! > targetModDate
      }
    }
  }
}

private extension File {
  /**
   Responsible for configuring and rendering file layouts.
   */
  struct Layout {
    /**
     Rendering context.
     */
    let context: [String: String]

    /**
     Layout file.
     */
    let template: File

    /**
     Regex used to determine where content should be rendered inside the layout.
     */
    nonisolated(unsafe) private static var pattern = Regex {
      ZeroOrMore(.whitespace); "@content"; ZeroOrMore(.whitespace)
    }

    /**
     Renders the layout around its given content and
     passes the updated context back to the calling file.
     
     Nested rendering is recursive.
     */
    func render(_ content: String) throws -> (String, [String: String]) {
      var text = try template.contents

      for match in text.comments(Self.pattern) {
        text = text.replacingOccurrences(of: match, with: content)
      }

      var context = context.merging(try template.source.metadata,
        uniquingKeysWith: { (x, _) in x })

      if let template = try template.source.template {
        (text, context) = try Layout(context: context, template: template)
          .render(text)
      }

      return (text, context)
    }
  }
}

private extension File {
  /**
   Responsible for configuring and rendering file includes.
   */
  struct Include {
    /**
     `@include` statement to be replaced in the origin file.
     */
    let fragment: String

    /**
     Regex used to determine where includes should be rendered inside the origin file.
     */
    nonisolated(unsafe) static let pattern = Regex {
      ZeroOrMore(.whitespace); "@include"; ZeroOrMore(.any, .reluctant)
    }

    /**
     Returns the file to include and any inline context from the `fragment`.
     */
    var parse: (File, [String: String])? {
      guard let comment = fragment.comment?
        .replacingFirst(of: "@include")
      else { return nil }

      let pattern = Regex {
        OneOrMore(.whitespace); "@"; OneOrMore(.any, .reluctant); ":"
      }

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

    /**
     Renders the include file contents with the given context.
     */
    func render(_ context: [String: String]) throws -> String {
      guard let (file, args) = parse else { return fragment }
      let context = context.merging(args, uniquingKeysWith: { (_, x) in x })
      return try file.render(context)
    }
  }
}

extension File {
  /**
   Responsible for rendering variables.
   */
  struct Variable {
    /**
     `@variable` statement to be replaced in the origin file.
     */
    var fragment: String

    /**
     Regex used to determine where variables should be rendered inside the origin file.
     */
    nonisolated(unsafe) static let pattern = Regex {
      ZeroOrMore(.whitespace); "@"; OneOrMore(.any, .reluctant)
    }

    /**
     Renders the variable from the given context.
     
     Context order–of–operations: inline > given > fallback.
     */
    func render(_ context: [String: String]) -> String {
      guard let comment = fragment.comment else { return fragment }

      let parts = comment
        .split(separator: "??", maxSplits: 1)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

      guard
        parts.first?.split(separator: " ").count == 1,
        let key = parts.first
      else { return fragment }

      return context[key] != nil
      ? context[key]! : parts.count == 2
      ? parts.last!   : fragment
    }
  }
}

/**
 Responsible for watching `Project.source` for changes and triggering rebuilds.
 */
struct Watcher {
  // Here be dragons!
  // `FSEventStream` doesn’t surface ideal events and isn’t Swift–friendly.
  // Know what you’re doing if you wade into this one.
  
  /**
   Starts a file system even stream attached to `Project.source`.
   */
  static func run() {
    let stream: FSEventStreamRef = FSEventStreamCreate(
      nil, onChange, nil,
      [Project.source.path(percentEncoded: false) as NSString] as NSArray,
      UInt64(kFSEventStreamEventIdSinceNow), 1.0,
      FSEventStreamEventFlags(kFSEventStreamCreateFlagFileEvents))!
    FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
    FSEventStreamStart(stream)
  }

  /**
   Triggers a rebuild whenever `Project.source` files are modified.
   */
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

/**
 Responsible for running `Project.target` on a localhost web server.
 */
struct Server {
  /**
   Starts the server on the given port.
   */
  static func run(port: UInt16) {
    let listener = try! NWListener(using: .tcp, on: NWEndpoint.Port(rawValue:port)!)

    listener.newConnectionHandler = { (_ conn) in
      conn.start(queue: .main)
      Server.receive(from: conn)
    }

    listener.start(queue: .main)
  }

  /**
   Handles incoming requests.
   */
  private static func receive(from conn: NWConnection) {
    conn.receive(minimumIncompleteLength: 1, maximumLength: conn.maximumDatagramSize)
    { data, _, complete, error in
			if let error { print("[serve] Error:", error.localizedDescription) }
			else if let data, let req = Request(data) { respond(on:conn, req:req) }
			if !complete { receive(from: conn) }
		}
  }

  /**
   Responds to requests.

   Only GET requests are supported.

   First attempts to match the exact request path, falling back on:

   1. <path>/index.html
   2. <path>/index.htm
   3. <path>.html
   4. <path>.htm
   */
  private static func respond(on conn: NWConnection, req: Request) {
    let refs = [req.path,
      "\(req.path)/index.html", "\(req.path)/index.htm",
      "\(req.path).html",       "\(req.path).htm"
    ].map { $0.split(separator: "/").joined(separator: "/") }

    guard
      let found = refs.first(where: {
        let file = URL(filePath: $0, relativeTo: Project.target)
        return file.exists && !file.isDirectory }),
      let res = try? Response(
        at: URL(filePath: found, relativeTo: Project.target))
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

private extension Server {
  /**
   Parsed HTTP request.
   */
  struct Request {
    /**
     Request path with the domain and port removed.
     */
    let path: String

    /**
     Content type from the request path extension.

     No extension, .html, and .htm are considered `.html`.
     Everything else is considered `.plainText`.
     */
    var contentType: UTType {
      let ext = URL(string: path)!.pathExtension
      return ext == "" || ["html", "htm"].contains(ext) ? .html : .plainText
    }

    /**
     Creates a `Request` from an HTTP request.
     */
    init?(_ data: Data) {
      let req = String(data: data, encoding: .utf8)!.components(separatedBy: "\r\n")
      guard let line = req.first, req.last!.isEmpty else { return nil }
      let components = line.components(separatedBy: " ")
      guard components.count == 3 else { return nil }
      self.path = components[1]
    }
  }
}

private extension Server {
  /**
   Response that can be returned over HTTP.
   */
  struct Response {
    /**
     Reponse status.

     Either `200 OK` or `404 Not Found`.
     */
    let status:Status
    enum Status: Int, CustomStringConvertible {
      case ok       = 200
      case notFound = 404

      var description: String {
        switch self {
          case .ok:       "OK"
          case .notFound: "Not Found"
        }
      }
    }

    /**
     Response body as data.
     */
    private let body: Data

    /**
     `Content-Length` and `Content-Type`.
     */
    private let headers: [Header: String]
    enum Header: String {
      case contentLength = "Content-Length"
      case contentType   = "Content-Type"
    }

    /**
     Formatted HTTP response.
     */
    var data: Data {
      var lines = ["HTTP/1.1 \(status.rawValue) \(status)"]
      lines.append(contentsOf: headers.map { "\($0.key.rawValue): \($0.value)" })
      lines.append(""); lines.append("")
      return lines.joined(separator: "\r\n").data(using: .utf8)! + body
    }

    /**
     Creates a new `Response` with given attributes.
     
     If status is set to `.notFound` and the request was for `.html`,
     this checks for `<Project.target>/404.html` to return in the body.
     */
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
        ].compactMapValues { $0 },
        uniquingKeysWith: { _, x in x })
    }

    /**
     Creates a new `Response` from a given file location.
     */
    init(at url: URL) throws {
      self.init(body: try Data(contentsOf: url), contentType: try url.contentType)
    }
  }
}

extension MarkdownParser {
  /**
  Singleton of `MarkdownParser`.
  
  Use this whenever the default config is acceptable
  to avoid N+1 when building projecs with many files.
  */
  nonisolated(unsafe) static let shared = Self()
}

extension String {
  /**
  Parsed comment from the string.
  */
  var comment: Self? {
    let pattern = Capture { ZeroOrMore(.any, .reluctant) }
    let regex = ChoiceOf {
      Regex { "<!--"; pattern; "-->"            }
      Regex { "//";   pattern; Anchor.endOfLine }
      Regex { "/*";   pattern; "*/"             }
    }

    guard
      let matches = firstMatch(of: regex),
      let match = [matches.1, matches.2, matches.3].first(where: { $0 != nil })
    else { return nil }

    return match!.description.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /**
   List of all the comments in the string.
   */
  func comments(_ pattern: Regex<Substring> = Regex { ZeroOrMore(.any, .reluctant) })
  -> [String] {
    matches(of: ChoiceOf {
      Regex { "<!--"; pattern; "-->"            }
      Regex { "//";   pattern; Anchor.endOfLine }
      Regex { "/*";   pattern; "*/"             }
    }).map {self[$0.range].description}
  }

  /**
   Returns a new string in which the first occurrence
   of a target string is replaced by another given string.
   */
  func replacingFirst(of: Self, with: Self = "") -> Self {
    guard let range = range(of: of) else { return self }
    return replacingCharacters(in: range, with: with)
  }
}

extension URL {
  /**
   Possible runtime error cases.
   */
  enum Exception: Error, CustomStringConvertible {
    case resourceDoesNotExist
    case resourceIsADirectory
    case resourceIsNotADirectory

    var description: String {
      switch self {
        case .resourceDoesNotExist:    "Resource does not exist."
        case .resourceIsADirectory:    "Resource is a directory."
        case .resourceIsNotADirectory: "Resource is not a directory."
      }
    }
  }

  /**
   The resource’s content as a string.
   */
  var asString: String {
    get throws {
      guard exists       else { throw Exception.resourceDoesNotExist }
      guard !isDirectory else { throw Exception.resourceIsADirectory }
      return String(decoding: try Data(contentsOf: self), as: UTF8.self)
    }
  }

  /**
   Content type of the resource.
   */
  var contentType: UTType? {
    get throws {
      try resourceValues(forKeys: [.contentTypeKey]).contentType
    }
  }

  /**
   Standardized file path without percent encoding.
   */
  var decodedPath: String { standardizedFileURL.path(percentEncoded: false) }

  /**
   Determines if the path contains another given URL’s path.
   */
  func encloses(_ url: URL) -> Bool {
    guard isDirectory else { return false }
    let sup = standardizedFileURL.pathComponents
    let sub = url.standardizedFileURL.pathComponents
    return sup.count < sub.count && !zip(sup, sub).contains(where: !=)
  }

  /**
   Determines if the resource exists.
   */
  var exists: Bool { FileManager.default.fileExists(atPath: decodedPath) }

  /**
   Determines if a resource is a directory.

   > This uses the old school Objective-C method.
   > The new Swift method only looks at the path,
   > returning false positives on files that do not have extensions.
   */
  var isDirectory: Bool {
    guard exists else { return false }
    var isDir:ObjCBool = false
    FileManager.default.fileExists(atPath: decodedPath, isDirectory: &isDir)
    return isDir.boolValue
  }

  /**
   Determines if a directory is empty.
   */
  var isEmpty: Bool {
    get throws {
      guard exists      else { throw Exception.resourceDoesNotExist    }
      guard isDirectory else { throw Exception.resourceIsNotADirectory }

      return try FileManager.default
        .contentsOfDirectory(atPath: decodedPath)
        .isEmpty
    }
  }

  /**
   Determines if a file or any directory in its path is ignored (e.g. dotfiles).

   Only path components after the given `relativeTo` path are considered.
   */
  func isIgnored(relativeTo: URL = URL(filePath: "/")) -> Bool {
    var components = standardizedFileURL.pathComponents

    if relativeTo.encloses(self) {
      components = components
        .dropFirst(relativeTo.standardizedFileURL.pathComponents.count)
        .map { String($0) }
    }

    return components.contains(where: { $0.first == "." })
  }

  /**
   Determines if the resource matches a content type.
   */
  func isType(_ type: UTType) -> Bool {
    guard pathExtension.count > 0 else { return type == .directory }
    return UTType(filenameExtension:pathExtension)!.conforms(to:type)
  }

  /**
   The resource’s frontmatter.
   */
  var metadata: [String: String] {
    get throws {
      guard exists else { throw Exception.resourceDoesNotExist }
      return MarkdownParser.shared.parse(try asString).metadata
    }
  }

  /**
   `Date` the resource was last modified.
   */
  var modificationDate: Date? {
    get throws {
      guard exists else { throw Exception.resourceDoesNotExist }
      return try FileManager.default
        .attributesOfItem(atPath:decodedPath)[.modificationDate] as? Date
    }
  }

  /**
   The `File` specified as the `@layout` in the resource’s metadata.
   */
  var template: File? {
    get throws {
      guard let path = try metadata["@layout"] else { return nil }
      return Project.find(path)
    }
  }

  /**
   Updates the resource’s modification date to `Date.now`.
   */
  func touch() throws {
    var (file, resourceValues) = (self, URLResourceValues())
    resourceValues.contentModificationDate = Date.now
    try file.setResourceValues(resourceValues)
  }
}

extension UTType { // Adds markdown files (.md) as a file type.
  /**
   Markdown (.md)

   **UTI:** net.daringfireball.markdown

   **conforms to:** public.plain-text
   */
  static var markdown: UTType {
    Self(exportedAs: "net.daringfireball.markdown", conformingTo: .plainText)
  }
}
