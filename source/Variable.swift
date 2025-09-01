import RegexBuilder

struct Variable {
  var fragment: String

  static let pattern = Regex {
    ZeroOrMore(.whitespace)
    "@"
    OneOrMore(.any, .reluctant)
  }

  func render(_ context: [String: String]) -> String {
    guard let comment = fragment.comment else { return fragment }

    let parts = comment
      .split(separator: "??", maxSplits: 1)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard parts.first?.split(separator: " ").count == 1, let key = parts.first
    else { return fragment }

    return context[key] != nil ? context[key]!
    : parts.count == 2 ? parts.last!
    : fragment
  }
}
