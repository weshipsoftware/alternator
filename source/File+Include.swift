import RegexBuilder

struct Include {
  let fragment: String

  static let pattern = Regex
    { ZeroOrMore(.whitespace); "@include"; ZeroOrMore(.any, .reluctant) }

  func render(_ context: [String: String]) throws -> String {
    guard let (file, args) = parse else { return fragment }
    let context = context.merging(args, uniquingKeysWith: { (_, x) in x })
    return try file.render(context)
  }

  var parse: (File, [String: String])? {
    guard let comment = fragment.comment?.replacingFirst(of: "@include")
     else { return nil }

    let pattern = Regex
      { OneOrMore(.whitespace); "@"; OneOrMore(.any, .reluctant); ":" }

    let parts = comment.split(separator: pattern)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard
      parts.count > 0,
      let ref = parts.first?.split(separator: "/").joined(separator: "/"),
      let file = File.find(ref),
      file.source.exists, file.source.isRenderable
    else { return nil }

    let keys: [String] = comment
      .matches(of: pattern)
      .map { comment[$0.range]
        .trimmingPrefix(.whitespace)
        .dropLast().description }
    let args: [String: String] = Dictionary(
      uniqueKeysWithValues: zip(keys, parts.dropFirst()))

    return (file, args)
  }
}
