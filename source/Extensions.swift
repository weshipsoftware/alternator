import Foundation
import Ink

extension Array where Element: Hashable {
  var unique: [Element] { Array(Set(self)) }
}

extension FileHandle: @retroactive TextOutputStream {
  nonisolated(unsafe) static var stderr = FileHandle.standardError
  public func write(_ message: String) { write(message.data(using: .utf8)!) }
}

extension MarkdownParser {
  nonisolated(unsafe) static let shared = MarkdownParser()
}

extension String {
  var asRef: String { split(separator: "/").joined(separator: "/") }

  func find(_ pattern: String) -> [String] {
    let range = NSRange(location: 0, length: self.utf16.count)
    return try! NSRegularExpression(pattern: pattern)
      .matches(in: self, range: range)
      .map { (self as NSString).substring(with: $0.range) }
  }

  func replacingFirst(of: String, with: String = "") -> String {
    guard let range = range(of: of) else { return self }
    return replacingCharacters(in: range, with: with)
  }
}

extension URL {
  var contents: String {
    get throws { String(decoding: try Data(contentsOf: self), as: UTF8.self) }
  }

  var creationDate: Date? {
    do {
      return try FileManager.default
        .attributesOfItem(atPath: path())[FileAttributeKey.creationDate] as? Date
    }

    catch { return nil }
  }

  var exists: Bool { FileManager.default.fileExists(atPath: path(percentEncoded: false)) }

  var isDirectory: Bool { (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }

  var isIgnored: Bool {
    path()
      .split(separator: "/")
      .contains(where: { component in component.first == "!" })
  }

  var list: [URL] {
    guard exists else {return []}
    return FileManager.default
      .subpaths(atPath: path())!
      .filter {
        !$0
          .split(separator: "/")
          .contains(where: { component in component.first == "." }) }
      .map { appending(component: $0) }
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
