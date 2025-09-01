import Foundation
import Network
import UniformTypeIdentifiers

extension Project {
  static func serve(port: UInt16) {
    let listener = try! NWListener(
      using: .tcp,
      on: NWEndpoint.Port(rawValue: port)!)

    listener.newConnectionHandler = { (_ conn) in
      conn.start(queue: .main)
      Self.receive(from: conn)
    }

    listener.start(queue: .main)

    print("[serve] serving \(Project.target.description)",
          "at http://localhost:\(port)")
  }
}

private extension Project {
  static func receive(from conn: NWConnection) {
    conn.receive(
      minimumIncompleteLength: 1,
      maximumLength: conn.maximumDatagramSize)
    { data, _, complete, err in
      if let err { print("[serve] Error: \(err.localizedDescription)") }
      else if let data, let req = Request(data) { respond(on: conn, req: req) }
      if !complete { receive(from: conn) }
    }
  }

  static func respond(on conn: NWConnection, req: Request) {
    let path = Project.target.path().appending(req.path)
    let refs = [path, "\(path)/index.html", "\(path)/index.htm",
                      "\(path).html",       "\(path).htm"]
    guard
      let path = refs.first(where: {
        let file = URL(fileURLWithPath: $0)
        return file.exists && !file.isDirectory }),
      let res = try? Response(at: URL(fileURLWithPath: path))
    else {
      let res = Response(.notFound, contentType: req.contentType)
      print("[serve] \(req.path) (\(res.status.rawValue) \(res.status))")
      conn.send(content: res.data, completion: .idempotent)
      return
    }

    print("[serve] \(req.path) (\(res.status.rawValue) \(res.status)")
    conn.send(content: res.data, completion: .idempotent)
  }
}

fileprivate struct Request {
  let path: String

  init?(_ data: Data) {
    let request = String(data: data, encoding: .utf8)!
      .components(separatedBy: "\r\n")
    guard let requestLine = request.first, request.last!.isEmpty
    else { return nil }
    let components = requestLine.components(separatedBy: " ")
    guard components.count == 3 else { return nil }
    self.path = components[1]
  }

  var contentType: UTType {
    guard
      let fileName = path.split(separator: "/").last,
      let fileExtension = fileName.split(separator: ".").last,
      fileName != fileExtension
    else { return .html }
    return ["html", "htm"].contains(fileExtension) ? .html : .plainText
  }
}

fileprivate struct Response {
  let status: Status

  private let body:     Data
  private let headers: [Header: String]

  enum Header: String
    { case contentLength = "Content-Length", contentType = "Content-Type" }

  enum Status: Int, CustomStringConvertible {
    case ok = 200, notFound = 404
    var description: String {
      switch self {
        case .ok: "OK"
        case .notFound: "Not Found"
      }
    }
  }

  var data: Data {
    var headerLines = ["HTTP/1.1 \(status.rawValue) \(status)"]
    headerLines.append(
      contentsOf: headers.map { "\($0.key.rawValue): \($0.value)" })
    headerLines.append(""); headerLines.append("")
    return headerLines
      .joined(separator: "\r\n")
      .data(using: .utf8)!
      + body
  }

  init(_ status:  Status          = .ok,
           body:  Data            = Data(),
    contentType:  UTType?         = nil,
        headers: [Header: String] = [:])
  {
    self.status = status
    let notFoundFile = Project.target.appending(path: "404.html")
    self.body =
      status == .notFound
      && contentType == .html
      && notFoundFile.exists
    ? try! Data(contentsOf: notFoundFile) : body
    self.headers = headers.merging([
      .contentLength: String(self.body.count),
      .contentType: contentType?.preferredMIMEType
    ].compactMapValues { $0 }, uniquingKeysWith: { _, x in x })
  }

  init(at url: URL) throws {
    self.init(
      body: try Data(contentsOf: url),
      contentType: try url
        .resourceValues(forKeys: [.contentTypeKey])
        .contentType)
  }
}
