import Foundation
import Ink

struct File {
  let src: URL

  var contents: String { get throws {
    let text = try src.contents
    if src.pathExtension == "md" {return MarkdownParser.shared.html(from: text)}
    guard try !metadata.isEmpty else {return text}
    guard let match = text.find(#"---(\n|.)*?---\n"#).first else {return text}
    return text.replacingFirst(of: match)
  }}

  var deps: [File] { get throws {
    guard isRenderable else {return []}

    let files: [File?] = try contents
      .find(Include.pattern)
      .map {Include(fragment: $0).file}
      + [try layout]

    return try files
      .filter {$0 != nil && $0!.src.exists == true}
      .map {$0!}
      .flatMap {try [$0] + $0.deps}
      .map {$0.src}
      .unique
      .map {Self(src: $0)}
  }}

  var isModified: Bool { get throws {
    guard tgt.exists,
      let srcModDate = try src.modificationDate,
      let tgtModDate = try tgt.modificationDate,
      tgtModDate > srcModDate
    else {return true}

    return try deps.contains {try $0.src.modificationDate! > tgtModDate}
  }}

  var isRenderable: Bool {
    ["css", "htm", "html", "js", "md", "rss", "svg", "txt", "xml"]
      .contains(src.pathExtension)
  }

  var layout: File? { get throws {
    guard let ref = try metadata["#layout"] else {return nil}
    return Project.file(ref)
  }}

  var metadata: [String: String] { get throws
    {MarkdownParser.shared.parse(try src.contents).metadata} }

  var ref: String {src.rawPath.replacingFirst(of: Project.src!.path()).ref}

  var tgt: URL {
    let url = Project.tgt!.appending(path: ref)
    return url.pathExtension == "md"
    ? url.deletingPathExtension().appendingPathExtension("html")
    : url
  }

  func build() throws {
    guard try isModified, !src.isIgnored else {return}

    if tgt.exists {try FileManager.default.removeItem(at: tgt)}

    try FileManager.default.createDirectory(
      atPath: tgt.deletingLastPathComponent().path(percentEncoded: false),
      withIntermediateDirectories: true)

    if isRenderable {
      echo("[build] rendering \(src.masked) -> \(tgt.masked)")
      FileManager.default
        .createFile(atPath: tgt.rawPath, contents: try render().data(using: .utf8))
    } else {
      echo("[build] copying \(src.masked) -> \(tgt.masked)")
      try src.touch()
      try FileManager.default.copyItem(at: src, to: tgt)
      try tgt.touch()
    }
  }

  func render(_ context: [String: String] = [:]) throws -> String {
    var context = context.merging(try metadata, uniquingKeysWith: {(x, _) in x})
    var text    = try contents

    if let layout = try layout {
      let macro = Layout(content: text, template: layout)
      context = context
        .merging(try macro.template.metadata, uniquingKeysWith: {(x, _) in x})
      text = try macro.render()
    }

    for match in text.find(Include.pattern) {
      let macro = Include(fragment: match)
      if macro.file?.src.exists == true {
        var params = macro.parameters
        for (key, val) in params where context[val] != nil
          {params[key] = context[val]}
        text = text.replacingFirst(of: match, with: try macro.file!.render(params))
      }
    }

    for match in text
      .find(#"((<!--|/\*|/\*\*)\s*@[\s\S]*?(-->|\*/)|//[^\S\r\n]*@[^\n]*)"#) {
        let macro = Variable(fragment: match)
        if let value = context.contains(where: {$0.key == macro.key})
        ? context[macro.key] : macro.val
          {text = text.replacingFirst(of: match, with: value as String)}
    }

    for match in text
      .find(#"((<!--|/\*|/\*\*)\s*[\s\S]*?(-->|\*/)|//[^\S\r\n]*[^\n]*)"#)
        {text = text.replacingFirst(of: match, with: "")}

    if ["css", "js"].contains(src.pathExtension) {
      text = text
        .components(separatedBy: .newlines)
        .map {$0.trimmingCharacters(in: .whitespacesAndNewlines)}
        .joined()
    }

    return text
  }
}