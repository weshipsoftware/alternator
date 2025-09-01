import Foundation

struct Project {
  static var source: URL!
  static var target: URL!

  static func build() {
    do {
      try manifest.forEach { try $0.build() }
      try derivedData.filter(isOrphaned).forEach(removeItem)
      try derivedData.filter({ try $0.isEmpty }).forEach(removeItem)
    } catch { print("[error]", error.localizedDescription) }
  }
}

private extension Project {
  static var manifest: [File] {
    source.subpaths
      .filter { !$0.isDirectory }
      .filter { (!source.encloses(target) || !target.encloses($0)) }
      .filter { !$0.isIgnored }
      .map(File.init(source:))
  }

  static var derivedData: [URL] {
    target.subpaths
      .filter { !$0.isIgnored }
      .filter { (!target.encloses(source) || !source.encloses($0)) }
  }

  static func isOrphaned(url: URL) -> Bool {
    guard !url.isDirectory else { return false }
    return !manifest
      .map({ $0.target.formatted() })
      .contains(url.formatted())
  }

  static func removeItem(at: URL) throws {
    print("[build] deleting <target>",
          at.description.replacingFirst(of: target.description))
    try FileManager.default.removeItem(at: at)
  }
}
