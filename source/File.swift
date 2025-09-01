import Foundation

struct File {
  var source: URL
  var target: URL {
    let url = Project.target.appending(path: ref(.source))
    return url.pathExtension == "md"
    ? url.deletingPathExtension().appendingPathExtension("html")
    : url
  }

  static func find(_ ref: String) -> Self? {
    let ref = Project.source.path(percentEncoded: false).appending(ref)
    return Self(source: URL(fileURLWithPath: ref))
  }

  func build() throws {
    guard try isModified, !source.isIgnored else { return }

    if target.exists { try FileManager.default.removeItem(at: target) }

    try FileManager.default.createDirectory(
      atPath: target.deletingLastPathComponent().path(percentEncoded: false),
      withIntermediateDirectories: true)

    if source.isRenderable {
      print("[build] rendering \(ref(.source)) -> \(ref(.target))")
      FileManager.default.createFile(
        atPath: target.path(percentEncoded: false),
        contents: try render().data(using: .utf8))
    }

    else {
      print("[build] copying \(ref(.source)) -> \(ref(.target))")
      try source.touch()
      try FileManager.default.copyItem(at: source, to: target)
      try target.touch()
    }
  }

  func render(_ context: [String: String] = [:]) throws -> String {
    var text = try source.contents
    var context = context
      .merging(try source.metadata, uniquingKeysWith: { (x, _) in x })

    if let template = try source.template {
      (text, context) = try Layout(template: template, context: context)
        .render(text)
    }

    for fragment in text.comments(Include.pattern) {
      text = text.replacingFirst(
        of: fragment,
        with: try Include(fragment: fragment).render(context))
    }

    for fragment in text.comments(Variable.pattern) {
      text = text.replacingFirst(
        of: fragment,
        with: Variable(fragment: fragment).render(context))
    }

    return text
  }
}

fileprivate extension File {
  var dependencies: [Self] { get throws {
    guard source.isRenderable else { return [] }

    let files: [File?] = try source.contents
      .comments(Include.pattern)
      .map { Include(fragment: $0).parse?.0 }
    + [try source.template]

    return try files
      .filter { $0 != nil && $0!.source.exists == true }
      .flatMap { try [$0!] + $0!.dependencies }
      .map { $0.source }
      .reduce(into: Set<URL>(), { (array, file) in array.insert(file) })
      .map { Self(source: $0) }
  }}

  var isModified: Bool { get throws {
    guard
      target.exists,
      let sourceModDate = try source.modificationDate,
      let targetModDate = try target.modificationDate,
      targetModDate > sourceModDate
    else { return true }
    return try dependencies.contains
      { try $0.source.modificationDate! > targetModDate }
  }}

  enum Environment { case source, target }
  func ref(_ environment: Self.Environment) -> String {
    let env = switch environment {
      case .source: (directory: Project.source, path: source)
      case .target: (directory: Project.target, path: target)
    }

    return env.path.formatted()
      .replacingFirst(of: env.directory!.formatted())
      .split(separator: "/")
      .joined(separator: "/")
  }
}
