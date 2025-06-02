import Foundation
import Ink

extension Array where Element: Hashable { var unique: [Element] {Self(Set(self))} }

func echo(_ msg: String) {print(msg, to: &FileHandle.stderr)}

extension FileHandle: @retroactive TextOutputStream {
  nonisolated(unsafe) static var stderr = FileHandle.standardError
  public func write(_ message:String) {write(message.data(using:.utf8)!)}
}

extension MarkdownParser {nonisolated(unsafe) static let shared = Self()}

extension String {
  var ref: String {split(separator: "/").joined(separator: "/")}

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
  var contents: String { get throws
    {String(decoding: try Data(contentsOf: self), as: UTF8.self)} }

  var creationDate: Date? { do {
    return try FileManager.default
      .attributesOfItem(atPath: path())[.creationDate]
      as? Date
  } catch {return nil} }

  var exists: Bool {FileManager.default.fileExists(atPath: rawPath)}

  var isDirectory: Bool
    {(try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true}

  var isIgnored: Bool
    {path().split(separator: "/").contains(where: {x in x.first == "!"})}

  var list: [URL] {
    guard exists else {return []}

    return FileManager.default
      .subpaths(atPath: path())!
      .filter {!$0.split(separator: "/").contains(where: {x in x.first == "."})}
      .map {appending(component: $0)}
  }

  var masked: String {
    rawPath
      .replacingFirst(of: FileManager.default.currentDirectoryPath)
      .replacingFirst(of: "file:///")
      .ref
  }

  var modificationDate: Date? { get throws {
    try FileManager.default
      .attributesOfItem(atPath: rawPath)[.modificationDate]
      as? Date
  }}

  var rawPath: String {path(percentEncoded: false)}

  func touch() throws {
    var (file, resourceValues) = (self, URLResourceValues())
    resourceValues.contentModificationDate = Date.now
    try file.setResourceValues(resourceValues)
  }
}