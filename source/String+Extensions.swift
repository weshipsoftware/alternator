import RegexBuilder

extension String {
  var comment: Self? {
    let pattern = Capture { ZeroOrMore(.any, .reluctant) }
    let regex = ChoiceOf {
      Regex { "<!--"; pattern; "-->"            }
      Regex { "//";   pattern; Anchor.endOfLine }
      Regex { "/*";   pattern; "*/"             } }
    guard
      let matches = firstMatch(of: regex),
      let match = [matches.1, matches.2, matches.3].first(where: { $0 != nil })
    else { return nil }
    return match!.description.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func comments(_ pattern: Regex<Substring>
                = Regex { ZeroOrMore(.any, .reluctant) })
  -> [String] {
    matches(of: ChoiceOf {
      Regex { "<!--"; pattern; "-->"            }
      Regex { "//";   pattern; Anchor.endOfLine }
      Regex { "/*";   pattern; "*/"             } })
    .map { self[$0.range].description }
  }

  func replacingFirst(of: Self, with: Self = "") -> Self {
    guard let range = range(of: of) else { return self }
    return replacingCharacters(in: range, with: with)
  }
}
