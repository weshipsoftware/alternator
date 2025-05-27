import ArgumentParser
import Foundation
import Ink
import Network
import UniformTypeIdentifiers

@main
struct Alternator: ParsableCommand {
	static let configuration = CommandConfiguration(version: "2.1.0")

	@Argument(help: "Path to your source directory.", completion: .directory)
	var source: String
	@Argument(help: "Path to your target directory.", completion: .directory)
	var target: String

	@Flag(name: .shortAndLong, help: "Rebuild <source> as you save changes.")
	var watch = false

	@Option(name: .shortAndLong, help: "Serve <target> on localhost:<port>.")
	var port: UInt16?

	mutating func run() throws {
		Project.build()
		if watch   == true {Watcher()}
		if let port = port {Server(port: port)}
		if watch == true || port != nil {echo("^c to stop"); RunLoop.current.run()}
	}

	func validate() throws {
		Project.src = URL(string: source.ref, relativeTo: URL.currentDirectory())
		Project.tgt = URL(string: target.ref, relativeTo: URL.currentDirectory())

		guard Project.src!.exists else
			{ throw ValidationError("<source> does not exist.") }
		guard Project.src!.isDirectory else
			{ throw ValidationError("<source> must be a directory.") }
		guard Project.src!.masked != Project.tgt!.masked else
			{ throw ValidationError("<source> and <target> cannot be the same.") }
		guard !Project.tgt!.exists || Project.tgt!.isDirectory else
			{ throw ValidationError("<target> must be a directory.") }
	}
}

extension Array where Element: Hashable {var unique: [Element] {Self(Set(self))}}

struct Comment {static let pattern = #"((<!--|/\*|/\*\*)\s*[\s\S]*?(-->|\*/)|//[^\S\r\n]*[^\n]*)"#}

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
		let files: [File?] = try contents.find(Include.pattern).map({Include(fragment: $0).file}) + [try layout]
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

	var isRenderable: Bool
		{["css", "htm", "html", "js", "md", "rss", "svg", "txt", "xml"].contains(src.pathExtension)}

	var layout: File? { get throws {
		guard let ref = try metadata["#layout"] else {return nil}
		return Project.file(ref)
	}}

	var metadata: [String: String] {get throws {MarkdownParser.shared.parse(try src.contents).metadata}}

	var ref: String {src.rawPath.replacingFirst(of: Project.src!.path()).ref}

	var tgt: URL {
		let url = Project.tgt!.appending(path: ref)
		return url.pathExtension == "md" ? url.deletingPathExtension().appendingPathExtension("html") : url
	}

	func build() throws {
		guard try isModified, !src.isIgnored else {return}

		if tgt.exists {try FileManager.default.removeItem(at: tgt)}

		try FileManager.default.createDirectory(
			atPath: tgt.deletingLastPathComponent().path(percentEncoded: false),
			withIntermediateDirectories: true)

		if isRenderable {
			echo("[build] rendering \(src.masked) -> \(tgt.masked)")
			FileManager.default.createFile(atPath: tgt.path(percentEncoded: false), contents: try render().data(using: .utf8))
		} else {
			echo("[build] copying \(src.masked) -> \(tgt.masked)")
			try src.touch()
			try FileManager.default.copyItem(at: src, to: tgt)
			try tgt.touch()
		}
	}

	func render(_ context: [String: String] = [:]) throws -> String {
		var context = context.merging(try metadata, uniquingKeysWith: {(x, _) in x}), text = try contents

		if let layout = try layout {
			let macro = Layout(content: text, template: layout)
			context = context.merging(try macro.template.metadata, uniquingKeysWith: {(x, _) in x})
			text = try macro.render()
		}

		for match in text.find(Include.pattern) {
			let macro = Include(fragment: match)
			if macro.file?.src.exists == true {
				var params = macro.parameters
				for (key, val) in params where context[val] != nil {params[key] = context[val]}
				text = text.replacingFirst(of: match, with: try macro.file!.render(params))
			}
		}

		for match in text.find(Variable.pattern) {
			let macro = Variable(fragment: match)
			if let value = context.contains(where: { $0.key == macro.key }) ? context[macro.key]
			: macro.defaultValue {text = text.replacingFirst(of: match, with: value as String)}
		}

		for match in text.find(Comment.pattern) {text = text.replacingFirst(of: match, with: "")}

		if ["css", "js"].contains(src.pathExtension)
			{text = text.components(separatedBy: .newlines).map({$0.trimmingCharacters(in: .whitespacesAndNewlines)}).joined()}

		return text
	}
}

extension FileHandle: @retroactive TextOutputStream {
	nonisolated(unsafe) static var stderr = FileHandle.standardError
	public func write(_ message:String) {write(message.data(using:.utf8)!)}
}

struct Include {
	var fragment: String

	static let pattern = #"((<!--|/\*|/\*\*)\s*#include[\s\S]*?(-->|\*/)|//[^\S\r\n]*#include[^\n]*)"#

	var arguments: String? {
		for predicate in [#"//\s*#include\s+(?<args>.+?)"#, #"(<!--|/\*|/\*\*)\s*#include\s+(?<args>(.|\n)+?)(-->|\*/)"#]
			{if let match = try? Regex(predicate).wholeMatch(in: fragment) {return match["args"]?.substring?.description}}
		return nil
	}

	var file: File? {
		guard let ref = arguments?.split(separator: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) else
			{ return nil }
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
		let vals = args.split(separator: /(@\S+:|#\S+:)/).map {$0.trimmingCharacters(in: .whitespacesAndNewlines)}
		for (k, v) in zip(keys, vals) {params[k] = v.description}
		return params
	}
}

struct Layout {
	let content: String, template: File

	static let pattern = #"((<!--|/\*|/\*\*)\s*#content[\s\S]*?(-->|\*/)|//[^\S\r\n]*#content[^\n]*)"#

	func render() throws -> String {
		var text = try template.contents
		for match in text.find(Self.pattern) {text = text.replacingFirst(of: match, with: content)}
		if let ref = try template.metadata["#layout"], let file = Project.file(ref)
			{text = try Layout(content: text, template: file).render()}
		return text
	}
}

extension MarkdownParser {nonisolated(unsafe) static let shared = Self()}

struct Project {
	nonisolated(unsafe) static var src: URL?, tgt: URL?

	static var srcContainsTgt: Bool {tgt!.masked.contains(src!.masked)}
	static var tgtContainsSrc: Bool {src!.masked.contains(tgt!.masked)}

	static func build() {
		do {
			let manifest = src!.list
				.filter {!$0.isDirectory && !srcContainsTgt ? true : !$0.absoluteString.contains(tgt!.absoluteString)}
				.map {File(src: $0)}

			try manifest.forEach {try $0.build()}

			try tgt!.list
				.filter {
					!$0.isDirectory
					&& !manifest.map({$0.src.absoluteString}).contains($0.absoluteString)
					&& !manifest.map({$0.tgt.absoluteString}).contains($0.absoluteString)
					&& !$0.isIgnored}
				.forEach {
					echo("[build] deleting \($0.masked)")
					try FileManager.default.removeItem(at:$0)}

			try tgt!.list
				.filter {$0.isDirectory}
				.filter {!tgtContainsSrc ? true : !$0.absoluteString.contains(src!.absoluteString)}
				.filter {!$0.isIgnored}
				.filter {try FileManager.default.contentsOfDirectory(atPath: $0.path(percentEncoded: false)).isEmpty}
				.forEach {
					echo("[build] deleting \($0.masked)")
					try FileManager.default.removeItem(at: $0)}
		}

		catch {
			guard ["no such file", "doesn’t exist", "already exists", "couldn’t be removed."]
				.contains(where: error.localizedDescription.contains)
			else {echo("[build] Error: \(error.localizedDescription)"); exit(1)}
		}
	}

	static func file(_ ref: String) -> File?
		{src!.list.filter({!$0.isDirectory}).map({File(src: $0)}).first(where: {$0.ref == ref})}
}

final class Server: Sendable {
	struct Request {
		let headers: [String: String], method: String, path: String

		init?(_ data: Data) {
			let request = String(data: data, encoding: .utf8)!.components(separatedBy: "\r\n")
			guard let requestLine = request.first, request.last!.isEmpty else {return nil}

			let components = requestLine.components(separatedBy: " ")
			guard components.count == 3 else {return nil}
			(self.method, self.path) = (components[0], components[1])

			let headers = request.dropFirst()
				.map {$0.split(separator: ":", maxSplits: 1)}
				.filter {$0.count == 2}
				.map {($0[0].lowercased(), $0[1].trimmingCharacters(in: .whitespaces))}
			self.headers = Dictionary(headers, uniquingKeysWith: {x, _ in x})
		}
	}

	struct Response {
		let body: Data, headers: [Header: String], status: Status

		enum Header: String {case contentLength = "Content-Length", contentType = "Content-Type"}

		enum Status: Int, CustomStringConvertible {
			case ok = 200, notFound = 404
			var description: String { switch self {
				case .ok:       return "OK"
				case .notFound: return "Not Found"
			}}
		}

		var data: Data {
			var headerLines = ["HTTP/1.1 \(status.rawValue) \(status)"]
			headerLines.append(contentsOf: headers.map { "\($0.key.rawValue): \($0.value)"})
			headerLines.append(""); headerLines.append("")
			return headerLines.joined(separator: "\r\n").data(using: .utf8)! + body
		}

		init(_ status: Status = .ok, body: Data = Data(), contentType: UTType? = nil, headers: [Header: String] = [:]) {
			(self.status, self.body, self.headers) = (status, body, headers.merging(
				[.contentLength: String(body.count), .contentType: contentType?.preferredMIMEType]
					.compactMapValues {$0}, uniquingKeysWith: {_, x in x}))
		}

		init(filePath: String) throws {
			let url = URL(filePath: filePath)
			self.init(
				body: try Data(contentsOf: url),
				contentType: try url.resourceValues(forKeys: [.contentTypeKey]).contentType)
		}

		init(_ text: String, contentType: UTType = .plainText)
			{self.init(body: text.data(using: .utf8)!, contentType: contentType)}
	}

	let listener: NWListener

	@discardableResult init(port: UInt16) {
		self.listener = try! NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
		listener.newConnectionHandler = {(_ conn) in conn.start(queue: .main); self.receive(from: conn)}
		listener.start(queue: .main)
		echo("[serve] serving \(Project.tgt!.masked) at http://localhost:\(port)")
	}

	func receive(from conn: NWConnection) {
		conn.receive(minimumIncompleteLength: 1, maximumLength: conn.maximumDatagramSize) { content, _, complete, err in
			if let err {echo("[serve] Error: \(err)")}
			else if let content, let req = Request(content) {self.respond(on: conn, req: req)}
			if !complete {self.receive(from: conn)}
		}
	}

	func respond(on conn: NWConnection, req: Request) {
		let ref = (Project.tgt!.masked + req.path).ref
		let paths = [ref, "\(ref)/index.html", "\(ref)/index.htm", "\(ref).html", "\(ref).htm"]

		guard
			req.method == "GET",
			let path = paths.first(where: {
				let file = URL(string: $0, relativeTo: URL.currentDirectory())!
				return file.exists && !file.isDirectory }),
			let res = try? Response(filePath: path)
		else {
			let res = Response(.notFound)
			echo("[serve] \(req.path) (\(res.status.rawValue) \(res.status))")
			conn.send(content: res.data, completion: .idempotent)
			return
		}

		echo("[serve] \(req.path) (\(res.status.rawValue) \(res.status))")
		conn.send(content: res.data, completion: .idempotent)
	}
}

extension String {
	var ref: String {split(separator: "/").joined(separator: "/")}

	func find(_ pattern: String) -> [String] {
		try! NSRegularExpression(pattern: pattern)
			.matches(in: self, range: NSRange(location: 0, length: self.utf16.count))
			.map {(self as NSString).substring(with: $0.range)}
	}

	func replacingFirst(of: String, with: String = "") -> String {
		guard let range = range(of: of) else {return self}
		return replacingCharacters(in: range, with: with)
	}
}

extension URL {
	var contents: String { get throws { String(decoding: try Data(contentsOf: self), as: UTF8.self) }}

	var creationDate: Date? {
		do {
			let (path, key) = (path(), FileAttributeKey.creationDate)
			return try FileManager.default.attributesOfItem(atPath: path)[key] as? Date
		} catch {return nil}
	}

	var exists: Bool {FileManager.default.fileExists(atPath: rawPath)}

	var isDirectory: Bool {(try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true}

	var isIgnored: Bool {path().split(separator: "/").contains(where: { x in x.first == "!" })}

	var list: [URL] {
		guard exists else {return []}
		return FileManager.default
			.subpaths(atPath: path())!
			.filter {!$0.split(separator: "/").contains(where: { x in x.first == "." })}
			.map {appending(component: $0)}
	}

	var masked: String {
		rawPath
			.replacingFirst(of: FileManager.default.currentDirectoryPath)
			.replacingFirst(of: "file:///")
			.ref
	}

	var modificationDate: Date? { get throws
		{try FileManager.default.attributesOfItem(atPath: rawPath)[FileAttributeKey.modificationDate] as? Date}}

	var rawPath: String {path(percentEncoded: false)}

	func touch() throws {
		var (file, resourceValues) = (self, URLResourceValues())
		resourceValues.contentModificationDate = Date.now
		try file.setResourceValues(resourceValues)
	}
}

struct Variable {
	var fragment: String

	static let pattern = #"((<!--|/\*|/\*\*)\s*@[\s\S]*?(-->|\*/)|//[^\S\r\n]*@[^\n]*)"#

	var arguments: [String] {
		var args = ""
		for predicate in [#"//\s*@+(?<var>.+?)"#, #"(<!--|/\*|/\*\*)\s*@(?<var>(.|\n)+?)(-->|\*/)"#]
			{if let match = try? Regex(predicate).wholeMatch(in: fragment) {args = match["var"]!.substring!.description}}
		return args
			.split(separator: "??", maxSplits: 1)
			.map {$0.trimmingCharacters(in: .whitespacesAndNewlines)}
			.enumerated()
			.map {(i, arg) in i == 0 ? "@" + arg : arg}
	}

	var defaultValue: String? {arguments.count == 2 ? arguments.last : nil}
	var key:          String  {arguments.first!}
}

struct Watcher {
	let callback: FSEventStreamCallback = { (_, _, numEvents, eventPaths, _, _) in
		let bufferPointer = UnsafeBufferPointer(
			start: eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self),
			count: numEvents)

		let diffs = (0..<numEvents)
			.map {URL(fileURLWithFileSystemRepresentation: bufferPointer[$0], isDirectory: false, relativeTo: nil)}
			.unique
			.filter {$0.lastPathComponent != ".DS_Store"}

		guard !diffs
			.filter({
				guard Project.srcContainsTgt else {return true}
				return !$0.absoluteString.contains(Project.tgt!.absoluteString)})
			.isEmpty
		else {return}

		Project.build()
	}

	@discardableResult public init() {
		let stream = FSEventStreamCreate(nil, callback, nil,
			[Project.src!.path() as NSString] as NSArray,
			UInt64(kFSEventStreamEventIdSinceNow), 1.0,
			FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))!
		FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
		FSEventStreamStart(stream)
		echo("[watch] watching \(Project.src!.masked) for changes")
	}
}

func echo(_ msg: String) {print(msg, to: &FileHandle.stderr)}
