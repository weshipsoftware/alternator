import Foundation

struct Project {
  nonisolated(unsafe) static var source: URL?
  nonisolated(unsafe) static var target: URL?

  static var sourceContainsTarget: Bool { target!.masked.contains(source!.masked) }
  static var targetContainsSource: Bool { source!.masked.contains(target!.masked) }

  static func build() {
    do {
      let manifest = source!
        .list
        .filter { !$0.isDirectory }
        .filter {
          !sourceContainsTarget
          ? true
          : !$0.absoluteString.contains(target!.absoluteString) }
        .map { File(source: $0) }

      try manifest
        .filter { !$0.source.isIgnored }
        .filter { try $0.isModified }
        .forEach { try $0.build() }

      try target!.list
        .filter { !$0.isDirectory }
        .filter { !manifest.map({$0.source.absoluteString}).contains($0.absoluteString) }
        .filter { !manifest.map({$0.target.absoluteString}).contains($0.absoluteString) }
        .filter { !$0.isIgnored }
        .forEach {
          CLI.log("[build] deleting \($0.masked)")
          try FileManager.default.removeItem(at:$0) }

      try target!.list
        .filter { $0.isDirectory }
        .filter {
          !targetContainsSource
          ? true
          : !$0.absoluteString.contains(source!.absoluteString) }
        .filter { !$0.isIgnored }
        .filter { try FileManager.default
          .contentsOfDirectory(atPath: $0.path(percentEncoded: false))
          .isEmpty }
        .forEach {
          CLI.log("[build] deleting \($0.masked)")
          try FileManager.default.removeItem(at: $0) }
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
      .filter { !$0.isDirectory }
      .map { File(source: $0) }
      .first(where: { $0.ref == ref })
  }
}
