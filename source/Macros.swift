struct Comment {
  static let pattern = #"((<!--|/\*|/\*\*)\s*[\s\S]*?(-->|\*/)|//[^\S\r\n]*[^\n]*)"#
}

struct Include {
  var fragment: String

  static let pattern = #"((<!--|/\*|/\*\*)\s*#include[\s\S]*?(-->|\*/)|//[^\S\r\n]*#include[^\n]*)"#

  var arguments:String? {
    enum Predicate: String {
      case singleLine = #"//\s*#include\s+(?<args>.+?)"#
      case multiLine  = #"(<!--|/\*|/\*\*)\s*#include\s+(?<args>(.|\n)+?)(-->|\*/)"#
    }

    if let match = try? Regex(Predicate.singleLine.rawValue).wholeMatch(in: fragment) {
      return match["args"]?.substring?.description
    }

    if let match = try? Regex(Predicate.multiLine.rawValue).wholeMatch(in: fragment) {
      return match["args"]?.substring?.description
    }

    return nil
  }

  var file: File? {
    guard let ref = arguments?
      .split(separator: " ")
      .first?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    else { return nil }
    return Project.file(ref)
  }

  var parameters: [String: String] {
    var params: [String: String] = [:]

    guard let args = arguments?
      .split(separator: " ")
      .dropFirst()
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    else { return params }

    let keys = args
      .find(#"(@\S+:|#\S+:)"#)
      .map { $0.dropLast().description }

    let vals = args
      .split(separator: /(@\S+:|#\S+:)/)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    for (k, v) in zip(keys, vals) { params[k] = v.description }

    return params
  }
}

struct Layout {
  let content:  String
  let template: File

  static let pattern = #"((<!--|/\*|/\*\*)\s*#content[\s\S]*?(-->|\*/)|//[^\S\r\n]*#content[^\n]*)"#

  func render() throws -> String {
    var text = try template.contents

    for match in text.find(Layout.pattern) {
      text = text.replacingFirst(of: match, with: content)
    }

    if let ref = try template.metadata["#layout"], let file = Project.file(ref) {
      text = try Layout(content: text, template: file).render()
    }

    return text
  }
}

struct Variable {
  var fragment: String

  static let pattern = #"((<!--|/\*|/\*\*)\s*@[\s\S]*?(-->|\*/)|//[^\S\r\n]*@[^\n]*)"#

  var arguments: [String] {
    enum Predicate: String {
      case singleLine = #"//\s*@+(?<var>.+?)"#
      case multiLine  = #"(<!--|/\*|/\*\*)\s*@(?<var>(.|\n)+?)(-->|\*/)"#
    }

    var args = ""

    if let match = try? Regex(Predicate.singleLine.rawValue).wholeMatch(in: fragment) {
      args = match["var"]!.substring!.description
    }

    if let match = try? Regex(Predicate.multiLine.rawValue).wholeMatch(in: fragment) {
      args = match["var"]!.substring!.description
    }

    return args
      .split(separator: "??", maxSplits: 1)
      .map {$0.trimmingCharacters(in: .whitespacesAndNewlines)}
      .enumerated()
      .map { (i, arg) in i == 0 ? "@" + arg : arg }
  }

  var defaultValue: String? { arguments.count == 2 ? arguments.last : nil }

  var key: String { arguments.first! }
}
