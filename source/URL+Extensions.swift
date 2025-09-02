import Foundation
import Ink
import RegexBuilder

extension URL {
  var contents: String { get throws {
    let text = try rawValue
    guard pathExtension != "md"
     else { return Self.markdownParser.html(from: text) }
    guard
      try !metadata.isEmpty,
      let match = text.firstMatch(of: Regex {
        Anchor.startOfSubject
        "---"; ZeroOrMore(.any, .reluctant)
        "---"; Anchor.endOfLine
      })?.output.description
    else { return text }
    return text.replacingFirst(of: match)
  }}

  var description: String { formatted().removingPercentEncoding! }

  var exists: Bool { FileManager.default.fileExists(atPath: rawPath) }

  var isDirectory: Bool {
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: rawPath, isDirectory: &isDir)
    return isDir.boolValue
  }

  var isEmpty: Bool { get throws {
    guard isDirectory else { return false }
    return try FileManager.default.contentsOfDirectory(atPath: rawPath).isEmpty
  }}

  var isIgnored: Bool {
    let srcRef = rawPath.replacingFirst(of: Project.source.formatted())
    let tgtRef = rawPath.replacingFirst(of: Project.target.formatted())
    let ref = srcRef.count <= tgtRef.count ? srcRef : tgtRef
    return ref.split(separator: "/").contains(where: { x in x.first == "." })
  }

  var isRenderable: Bool {
    ["css", "htm", "html", "js", "md", "rss", "svg", "txt", "xml"]
      .contains(pathExtension)
  }

  static let markdownParser = MarkdownParser()

  var metadata: [String: String] { get throws
    { Self.markdownParser.parse(try rawValue).metadata }}

  var modificationDate: Date? { get throws {
    try FileManager.default
      .attributesOfItem(atPath: rawPath)[.modificationDate] as? Date
  }}

  var rawPath: String { path(percentEncoded: false) }

  var rawValue: String { get throws
    { String(decoding: try Data(contentsOf: self), as: UTF8.self) }}

  var subpaths: [Self] {
    guard exists else { return [] }
    return FileManager.default
      .subpaths(atPath: rawPath)!
      .map { appending(path: $0) }
  }

  var template: File? { get throws {
    guard let ref = try metadata["@layout"] else { return nil }
    return File.find(ref)
  }}

  func encloses(_ subDirectory: URL) -> Bool {
    subDirectory.standardizedFileURL.formatted()
      .contains(standardizedFileURL.formatted())
  }

  func touch() throws {
    var (file, resourceValues) = (self, URLResourceValues())
    resourceValues.contentModificationDate = Date.now
    try file.setResourceValues(resourceValues)
  }
}
