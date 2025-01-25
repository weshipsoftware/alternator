import Foundation
import Ink

struct Project {
  nonisolated(unsafe) static var source: URL?
  nonisolated(unsafe) static var target: URL?
  
  static var sourceContainsTarget: Bool {target!.masked.contains(source!.masked)}
  static var targetContainsSource: Bool {source!.masked.contains(target!.masked)}

  static func build() {
    do {
      let manifest = source!.list
        .filter {!$0.isDirectory}
        .filter {!sourceContainsTarget
          ? true : !$0.absoluteString.contains(target!.absoluteString)}
        .map {File(source: $0)}
      
      try buildFiles(manifest)
      try pruneFiles(manifest)
      try pruneFolders(manifest)
    }

    catch {
      guard ["no such file", "doesn’t exist", "already exists", "couldn’t be removed."]
        .contains(where:error.localizedDescription.contains)
      else {
        print(error)
        print("[build] Error: \(error.localizedDescription)", to:&FileHandle.stderr)
        exit(1)
      }
    }
  }

  static func file(_ ref: String) -> File? {
    source!.list
      .filter {!$0.isDirectory}
      .map {File(source:$0)}
      .first(where: {$0.ref == ref})
  }
}

private extension Project {
  static func buildFiles(_ manifest: [File]) throws {
    try manifest
      .filter {$0.source.lastPathComponent.prefix(1) != "!"}
      .filter {try $0.isModified}
      .forEach {try $0.build()}
  }
  
  static func pruneFiles(_ manifest: [File]) throws {
    try target!.list
      .filter {!$0.isDirectory}
      .filter {!manifest.map({$0.source.absoluteString}).contains($0.absoluteString)}
      .filter {!manifest.map({$0.target.absoluteString}).contains($0.absoluteString)}
      .forEach {
        print("[build] deleting \($0.masked)", to:&FileHandle.stderr)
        try FileManager.default.removeItem(at:$0)}
  }
  
  static func pruneFolders(_ manifest: [File]) throws {
    try target!.list
      .filter {$0.isDirectory}
      .filter {!targetContainsSource ? true : !$0.absoluteString.contains(source!.absoluteString)}
      .filter {try FileManager.default
        .contentsOfDirectory(atPath:$0.path(percentEncoded:false))
        .isEmpty}
      .forEach {
        print("[build] deleting \($0.masked)", to:&FileHandle.stderr)
        try FileManager.default.removeItem(at:$0)}
  }
}

struct File {
  let source: URL
  
  var contents: String { get throws {
    let text = try source.contents
    if source.pathExtension == "md" {return File.parser.html(from:text)}
    if try metadata.isEmpty == true {return text}
    if let match = text.find(#"---(\n|.)*?---\n"#).first {return text.replacingFirst(of:match)}
    return text
  }}
  
  var isModified: Bool { get throws {
    guard target.exists,
      let sourceModDate = try source.modificationDate,
      let targetModDate = try target.modificationDate,
      targetModDate > sourceModDate
    else {return true}
    return try dependencies.contains
      {try $0.source.modificationDate! > targetModDate}
  }}

  var metadata: [String: String] { get throws
    {File.parser.parse(try source.contents).metadata}}

  var ref: String
    {source.path(percentEncoded:false).replacingFirst(of:Project.source!.path()).asRef}

  var target: URL {
    let url = Project.target!.appending(path:ref)
    return url.pathExtension == "md"
    ? url.deletingPathExtension().appendingPathExtension("html") : url
  }

  func build() throws {
    if target.exists
      {try FileManager.default.removeItem(at:target)}

    try FileManager.default.createDirectory(
      atPath: target.deletingLastPathComponent().path(percentEncoded:false),
      withIntermediateDirectories:true)

    if isRenderable {
      print("[build] rendering \(source.masked) -> \(target.masked)", to: &FileHandle.stderr)
      let (file, text) = (target.path(percentEncoded:false), try render().data(using:.utf8))
      FileManager.default.createFile(atPath:file, contents:text)
    }
    
    else {
      print("[build] copying \(source.masked) -> \(target.masked)", to: &FileHandle.stderr)
      try source.touch()
      try FileManager.default.copyItem(at:source, to:target)
      try target.touch()
    }
  }
}

private extension File {
  nonisolated(unsafe) static let parser = MarkdownParser()
  
  var dependencies: [File] { get throws {
    guard isRenderable else {return []}

    let deps: [File?] =
      try contents.find(Include.pattern).map {Include(fragment:$0).file} + [try layout]

    return try deps
      .filter({$0 != nil && $0!.source.exists == true}).map {$0!}
      .flatMap({try [$0] + $0.dependencies}).map {$0.source}
      .unique.map {File(source: $0)}
  }}

  var isRenderable: Bool
    {["css", "htm", "html", "js", "md", "rss", "svg", "txt", "xml"].contains(source.pathExtension)}

  var layout: File? { get throws {
    guard let ref = try metadata["#layout"] else {return nil}
    return Project.file(ref)
  }}

  func render(_ context: [String: String] = [:]) throws -> String {
    var context = context.merging(try metadata, uniquingKeysWith: {(x, _) in x})
    var text    = try contents
  
    if let layout = try layout {
      let macro = Layout(content:text, template:layout)
      context = context.merging(try macro.template.metadata, uniquingKeysWith: {(x, _) in x})
      text = try macro.render()
    }
  
    for match in text.find(Include.pattern) {
      let macro = Include(fragment:match)
      if macro.file?.source.exists == true {
        var params = macro.parameters
        for (key, val) in params where context[val] != nil {params[key] = context[val]}
        if params["#closure"] == "true" {
          params.removeValue(forKey:"#closure")
          params = params.merging(context, uniquingKeysWith: {(x, _) in x})}
        text = text.replacingFirst(of:match, with:try macro.file!.render(params))
      }
    }
  
    for match in text.find(Variable.pattern) {
      let macro = Variable(fragment:match)
      if let value = context.contains(where: {$0.key == macro.key})
      ? context[macro.key] : macro.defaultValue
        {text = text.replacingFirst(of: match, with: value as String)}
    }
  
    return text
  }
}

struct Layout {
  let content  : String
  let template : File
  
  static let pattern =
    #"((<!--|/\*|/\*\*)\s*#content[\s\S]*?(-->|\*/)|//[^\S\r\n]*#content[^\n]*)"#
  
  func render() throws -> String {
    var text = try template.contents
    
    for match in text.find(Layout.pattern)
      {text = text.replacingFirst(of:match, with:content)}
    
    if let ref = try template.metadata["#layout"], let file = Project.file(ref)
      {text = try Layout(content:text, template:file).render()}
    
    return text
  }
}

struct Include {
  var fragment: String
  
  static let pattern =
    #"((<!--|/\*|/\*\*)\s*#include[\s\S]*?(-->|\*/)|//[^\S\r\n]*#include[^\n]*)"#
  
  var file: File? {
    guard let ref = arguments?
      .split(separator:" ").first?
      .trimmingCharacters(in:.whitespacesAndNewlines)
    else {return nil}
    return Project.file(ref)
  }
  
  var parameters: [String: String] {
    var params: [String: String] = [:]

    guard let args = arguments?
      .split(separator:" ").dropFirst().joined(separator:" ")
      .trimmingCharacters(in:.whitespacesAndNewlines)
    else {return params}

    let keys = args.find(#"(@\S+:|#\S+:)"#)
      .map {$0.dropLast().description}
    let vals = args.split(separator:/(@\S+:|#\S+:)/)
      .map {$0.trimmingCharacters(in:.whitespacesAndNewlines)}

    for (k, v) in zip(keys, vals) {params[k] = v.description}

    return params
  }
}

private extension Include {
  var arguments:String? {
    enum Predicate: String {
      case singleLine = #"//\s*#include\s+(?<args>.+?)"#
      case multiLine  = #"(<!--|/\*|/\*\*)\s*#include\s+(?<args>(.|\n)+?)(-->|\*/)"#
    }
    
    if let match = try? Regex(Predicate.singleLine.rawValue).wholeMatch(in:fragment)
      {return match["args"]?.substring?.description}

    if let match = try? Regex(Predicate.multiLine.rawValue).wholeMatch(in:fragment)
      {return match["args"]?.substring?.description}

    return nil
  }
}

struct Variable {
  var fragment: String
  
  static let pattern =
    #"((<!--|/\*|/\*\*)\s*@[\s\S]*?(-->|\*/)|//[^\S\r\n]*@[^\n]*)"#

  var defaultValue: String?
    {arguments.count == 2 ? arguments.last : nil}

  var key: String
    {arguments.first!}
}

private extension Variable {
  var arguments:[String] {
    var args = ""
    
    enum Predicate: String {
      case singleLine = #"//\s*@+(?<var>.+?)"#
      case multiLine  = #"(<!--|/\*|/\*\*)\s*@(?<var>(.|\n)+?)(-->|\*/)"#
    }
        
    if let match = try? Regex(Predicate.singleLine.rawValue).wholeMatch(in:fragment)
      {args = match["var"]!.substring!.description}
    
    if let match = try? Regex(Predicate.multiLine.rawValue).wholeMatch(in:fragment)
      {args = match["var"]!.substring!.description}
    
    return args
      .split(separator:"??", maxSplits:1)
      .map {$0.trimmingCharacters(in:.whitespacesAndNewlines)}
      .enumerated()
      .map {(i, arg) in
        guard i == 0 else {return arg}
        return "@" + arg}
  }
}

extension Array where Element: Hashable {
  var unique: [Element]
    {Array(Set(self))}
}

extension String {
  var asRef: String
    {split(separator:"/").joined(separator:"/")}

  func find(_ pattern: String) -> [String] {
    try! NSRegularExpression(pattern:pattern)
      .matches(in:self, range: NSRange(location:0, length:self.utf16.count))
      .map {(self as NSString).substring(with:$0.range)}
  }
  
  func replacingFirst(of: String, with: String = "") -> String {
    guard let range = range(of:of) else {return self}
    return replacingCharacters(in:range, with:with)
  }
}

extension URL {
  var contents: String { get throws
    {String(decoding: try Data(contentsOf:self), as: UTF8.self)}}
  
  var exists:Bool {
    let file = path(percentEncoded:false)
    var isDir: ObjCBool = true
    return FileManager.default.fileExists(atPath:file, isDirectory:&isDir)
  }
  
  var isDirectory: Bool
    {(try? resourceValues(forKeys:[.isDirectoryKey]))?.isDirectory == true}

  var list: [URL] {
    guard exists else { return [] }
    let file = path()
    return FileManager.default
      .subpaths(atPath:file)!
      .filter {!$0.contains(".DS_Store")}
      .map {appending(component: $0)}
  }
  
  var masked:String {
    path(percentEncoded:false)
      .replacingFirst(of:FileManager.default.currentDirectoryPath)
      .replacingFirst(of:"file:///")
      .asRef
  }

  var modificationDate: Date? { get throws {
    let (file, key) = (path(percentEncoded:false), FileAttributeKey.modificationDate)
    return try FileManager.default.attributesOfItem(atPath:file)[key] as? Date
  }}
  
  func touch() throws {
    var (file, resourceValues) = (self, URLResourceValues())
    resourceValues.contentModificationDate = Date()
    try file.setResourceValues(resourceValues)
  }
}