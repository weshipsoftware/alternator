import Foundation
import Network
import UniformTypeIdentifiers

struct Request {
  let path: String

  init?(_ data: Data) {
    let request = String(data: data, encoding: .utf8)!.components(separatedBy: "\r\n")
    guard let requestLine = request.first, request.last!.isEmpty else {return nil}

    let components = requestLine.components(separatedBy: " ")
    guard components.count == 3 else {return nil}
    self.path = components[1]
  }

  var contentType: UTType {
    guard
      let fileName = path.split(separator: "/").last,
      let fileExtension = fileName.split(separator: ".").last,
      fileName != fileExtension
    else {return .html}
    return ["html", "htm"].contains(fileExtension) ? .html : .plainText
  }
}

struct Response {
  let body: Data, headers: [Header: String], status: Status

  enum Header: String
    {case contentLength = "Content-Length", contentType = "Content-Type"}

  enum Status: Int, CustomStringConvertible {
    case ok = 200, notFound = 404
    var description: String { switch self {
      case .ok:       return "OK"
      case .notFound: return "Not Found"
    }}
  }

  var data: Data {
    var headerLines = ["HTTP/1.1 \(status.rawValue) \(status)"]
    headerLines.append(contentsOf: headers.map {"\($0.key.rawValue): \($0.value)"})
    headerLines.append(""); headerLines.append("")
    return headerLines.joined(separator: "\r\n").data(using: .utf8)! + body
  }

  init(_ status: Status  = .ok,     body:  Data            = Data(),
    contentType: UTType? = nil,  headers: [Header: String] = [:]
  ) {
    self.status = status

    let notFoundFile = Project.tgt!.appending(path: "404.html")
    self.body = status == .notFound && contentType == .html && notFoundFile.exists
    ? try! Data(contentsOf: notFoundFile) : body

    self.headers = headers.merging(
      [ .contentLength: String(self.body.count),
        .contentType:   contentType?.preferredMIMEType ]
      .compactMapValues {$0}, uniquingKeysWith: {_, x in x})
  }

  init(filePath: String) throws {
    let file = URL(filePath: filePath)
    self.init(
      body: try Data(contentsOf: file),
      contentType: try file.resourceValues(forKeys: [.contentTypeKey]).contentType)
  }
}

final class HTTPServer: Sendable {
  let listener: NWListener

  @discardableResult init(port: UInt16) {
    self.listener = try! NWListener(
      using: .tcp,
      on: NWEndpoint.Port(rawValue: port)!)

    listener.newConnectionHandler = { (_ conn) in
      conn.start(queue: .main)
      self.receive(from: conn)
    }

    listener.start(queue: .main)

    echo("[serve] serving \(Project.tgt!.masked) at http://localhost:\(port)")
  }

  func receive(from conn: NWConnection) {
    conn.receive(minimumIncompleteLength: 1, maximumLength: conn.maximumDatagramSize)
    { content, _, complete, err in
      if let err {echo("[serve] Error: \(err)")}
      else if let content, let req = Request(content)
        {self.respond(on: conn, req: req)}
      if !complete {self.receive(from: conn)}
    }
  }

  func respond(on conn: NWConnection, req: Request) {
    let ref  = (Project.tgt!.masked + req.path).ref
    let refs = [ref,
      "\(ref)/index.html", "\(ref)/index.htm",
      "\(ref).html",       "\(ref).htm"]

    guard
      let path = refs.first(where: {
        let file = URL(string: $0, relativeTo: URL.currentDirectory())!
        return file.exists && !file.isDirectory }),
      let res = try? Response(filePath: path)
    else {
      let res = Response(.notFound, contentType: req.contentType)
      echo("[serve] \(req.path) (\(res.status.rawValue) \(res.status))")
      conn.send(content: res.data, completion: .idempotent)
      return
    }

    echo("[serve] \(req.path) (\(res.status.rawValue) \(res.status))")
    conn.send(content: res.data, completion: .idempotent)
  }
}