import RegexBuilder

struct Layout {
  let template: File, context: [String: String]

  private static var pattern = Regex
    { ZeroOrMore(.whitespace); "@content"; ZeroOrMore(.whitespace) }

  func render(_ content: String) throws -> (String, [String: String]) {
    var text = try template.source.contents
    for match in text.comments(Self.pattern)
      { text = text.replacingOccurrences(of: match, with: content) }
    var context = context
      .merging(try template.source.metadata, uniquingKeysWith: { (x, _) in x })
    if let template = try template.source.template {
      (text, context) = try Layout(template: template, context: context)
        .render(text) }
    return (text, context)
  }
}
