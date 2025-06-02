import Foundation

struct Project {
  nonisolated(unsafe) static var src: URL?, tgt: URL?

  static var srcContainsTgt: Bool {tgt!.masked.contains(src!.masked)}
  static var tgtContainsSrc: Bool {src!.masked.contains(tgt!.masked)}

  static func build() {
    do {
      let manifest = src!.list
        .filter {
          !$0.isDirectory &&
          !srcContainsTgt ? true : !$0.absoluteString.contains(tgt!.absoluteString) }
        .map {File(src: $0)}

      try manifest.forEach {try $0.build()}

      try tgt!.list
        .filter {
          !$0.isDirectory
          && !manifest.map({$0.src.absoluteString}).contains($0.absoluteString)
          && !manifest.map({$0.tgt.absoluteString}).contains($0.absoluteString)
          && !$0.isIgnored }
        .forEach {
          echo("[build] deleting \($0.masked)")
          try FileManager.default.removeItem(at:$0) }

      try tgt!.list
        .filter {
          $0.isDirectory
          && (!tgtContainsSrc ? true
            : !$0.absoluteString.contains(src!.absoluteString))
          && !$0.isIgnored }
        .filter { try FileManager.default
          .contentsOfDirectory(atPath: $0.path(percentEncoded: false)).isEmpty }
        .forEach {
          echo("[build] deleting \($0.masked)")
          try FileManager.default.removeItem(at: $0) }
    }

    catch {
      guard
        ["no such file", "doesn’t exist", "already exists", "couldn’t be removed."]
          .contains(where: error.localizedDescription.contains)
      else {
        echo("[build] Error: \(error.localizedDescription)")
        exit(1)
      }
    }
  }

  static func file(_ ref: String) -> File? {
    src!.list
      .filter {!$0.isDirectory}
      .map {File(src: $0)}
      .first(where: {$0.ref == ref})
  }
}