import Foundation
import Ink

struct File {
  let source: URL

  var contents: String {
    get throws {
      let text = try source.contents
      if source.pathExtension == "md" { return MarkdownParser.shared.html(from: text) }
      guard try !metadata.isEmpty else { return text }
      guard let match = text.find(#"---(\n|.)*?---\n"#).first else { return text }
      return text.replacingFirst(of: match)
    }
  }

  var dependencies: [File] {
    get throws {
      guard isRenderable else { return [] }

      let deps: [File?] = try contents
        .find(Include.pattern)
        .map { Include(fragment: $0).file } + [try layout]

      return try deps
        .filter { $0 != nil && $0!.source.exists == true }
        .map { $0! }
        .flatMap { try [$0] + $0.dependencies }
        .map { $0.source }
        .unique
        .map { File(source: $0) }
    }
  }

  var isModified: Bool {
    get throws {
      guard target.exists,
        let sourceModDate = try source.modificationDate,
        let targetModDate = try target.modificationDate,
        targetModDate > sourceModDate
      else { return true }

      return try dependencies.contains { try $0.source.modificationDate! > targetModDate }
    }
  }

  var isRenderable: Bool {
    ["css", "htm", "html", "js", "md", "rss", "svg", "txt", "xml"]
      .contains(source.pathExtension)
  }

  var layout: File? {
    get throws {
      guard let ref = try metadata["#layout"] else { return nil }
      return Project.file(ref)
    }
  }

  var metadata: [String: String] {
    get throws { MarkdownParser.shared.parse(try source.contents).metadata }
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
    if target.exists { try FileManager.default.removeItem(at: target) }

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
    var context = context.merging(try metadata, uniquingKeysWith: { (x, _) in x })
    var text    = try contents

    if let layout = try layout {
      let macro = Layout(content: text, template: layout)
      context = context.merging(try macro.template.metadata, uniquingKeysWith: { (x, _) in x })
      text = try macro.render()
    }

    for match in text.find(Include.pattern) {
      let macro = Include(fragment: match)
      if macro.file?.source.exists == true {
        var params = macro.parameters
        for (key, val) in params where context[val] != nil { params[key] = context[val] }
        text = text.replacingFirst(of: match, with: try macro.file!.render(params))
      }
    }

    for match in text.find(Variable.pattern) {
      let macro = Variable(fragment: match)
      if let value = context.contains(where: { $0.key == macro.key })
      ? context[macro.key]
      : macro.defaultValue {
        text = text.replacingFirst(of: match, with: value as String)
      }
    }

    for match in text.find(Comment.pattern) {
      text = text.replacingFirst(of: match, with: "")
    }

    if ["css", "js"].contains(source.pathExtension) {
      text = text
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .joined()
    }

    return text
  }
}
