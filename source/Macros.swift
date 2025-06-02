struct Include {
  var fragment: String

  static let pattern =
    #"((<!--|/\*|/\*\*)\s*#include[\s\S]*?(-->|\*/)|//[^\S\r\n]*#include[^\n]*)"#

  var arguments: String? {
    for predicate in [
      #"//\s*#include\s+(?<args>.+?)"#,
      #"(<!--|/\*|/\*\*)\s*#include\s+(?<args>(.|\n)+?)(-->|\*/)"#
    ] {
      if let match = try? Regex(predicate).wholeMatch(in: fragment)
        {return match["args"]?.substring?.description}
    }

    return nil
  }

  var file: File? {
    guard let ref = arguments?
      .split(separator: " ").first?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    else {return nil}

    return Project.file(ref)
  }

  var parameters: [String: String] {
    var params: [String: String] = [:]

    guard let args = arguments?
      .split(separator: " ")
      .dropFirst()
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    else {return params}

    let keys = args.find(#"(@\S+:|#\S+:)"#).map {$0.dropLast().description}

    let vals = args
      .split(separator: /(@\S+:|#\S+:)/)
      .map {$0.trimmingCharacters(in: .whitespacesAndNewlines)}

    for (k, v) in zip(keys, vals) {params[k] = v.description}

    return params
  }
}

struct Layout {
  let content: String, template: File

  func render() throws -> String {
    var text = try template.contents

    let _pattern =
      #"((<!--|/\*|/\*\*)\s*#content[\s\S]*?(-->|\*/)|//[^\S\r\n]*#content[^\n]*)"#
    for match in text.find(_pattern)
      {text = text.replacingFirst(of: match, with: content)}

    if let ref = try template.metadata["#layout"], let file = Project.file(ref)
      {text = try Layout(content: text, template: file).render()}

    return text
  }
}

struct Variable {
  var fragment: String

  var arguments: [String] {
    var args = ""

    for predicate in [
      #"//\s*@+(?<var>.+?)"#,
      #"(<!--|/\*|/\*\*)\s*@(?<var>(.|\n)+?)(-->|\*/)"#
    ] {
      if let match = try? Regex(predicate).wholeMatch(in: fragment)
        {args = match["var"]!.substring!.description}
    }

    return args
      .split(separator: "??", maxSplits: 1)
      .map {$0.trimmingCharacters(in: .whitespacesAndNewlines)}
      .enumerated()
      .map {(i, arg) in i == 0 ? "@" + arg : arg}
  }

  var val: String? {arguments.count == 2 ? arguments.last : nil}
  var key: String  {arguments.first!}
}