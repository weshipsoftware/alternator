import Foundation
import Network
import UniformTypeIdentifiers

struct Request {
  let headers     : [String: String]
  let httpVersion :  String
  let method      :  String
  let path        :  String
  
  init?(_ data: Data) {
    let request = String(data:data, encoding:.utf8)!.components(separatedBy:"\r\n")
    guard let requestLine = request.first, request.last!.isEmpty else {return nil}
    
    let components = requestLine.components(separatedBy:" ")
    guard components.count == 3 else {return nil}
    
    (self.method, self.path, self.httpVersion) = (components[0], components[1], components[2])
    
    let headerElements = request.dropFirst()
      .map {$0.split(separator:":", maxSplits:1)}
      .filter {$0.count == 2}
      .map {($0[0].lowercased(), $0[1].trimmingCharacters(in:.whitespaces))}
    self.headers = Dictionary(headerElements, uniquingKeysWith: {x, _ in x})
  }
}

struct Response {
  let body    :  Data
  let headers : [Header: String]
  let status  :  Status
  
  let httpVersion = "HTTP/1.1"
  
  enum Header: String {
    case contentLength = "Content-Length"
    case contentType   = "Content-Type"
  }
  
  enum Status: Int, CustomStringConvertible {
    case ok       = 200
    case notFound = 404
    case teapot   = 418
    
    var description: String {
      switch self {
        case .ok       : return "OK"
        case .notFound : return "Not Found"
        case .teapot   : return "I'm a teapot"
      }
    }
  }
  
  var data: Data {
    var headerLines = ["\(httpVersion) \(status.rawValue) \(status)"]
    headerLines.append(contentsOf:headers.map({"\($0.key.rawValue): \($0.value)"}))
    headerLines.append(""); headerLines.append("")
    return headerLines.joined(separator:"\r\n").data(using:.utf8)! + body
  }
  
  init(_ status :  Status          = .ok,
           body :  Data            = Data(),
    contentType :  UTType?         = nil,
        headers : [Header: String] = [:])
  {
    self.status  = status
    self.body    = body
    self.headers = headers.merging(
      [.contentLength:String(body.count), .contentType:contentType?.preferredMIMEType]
        .compactMapValues {$0},
      uniquingKeysWith: {_, x in x})
  }
  
  init(filePath: String) throws {
    let url  = URL(filePath:filePath)
    let data = try Data(contentsOf:url)
    let contentType = try url.resourceValues(forKeys:[.contentTypeKey]).contentType
    self.init(body:data, contentType:contentType)
  }
  
  init(_ text: String, contentType: UTType = .plainText)
    {self.init(body:text.data(using:.utf8)!, contentType:contentType)}
}

final class Server: Sendable {
  let callback : @Sendable (Request?, Response?, NWError?) -> Void
  let listener : NWListener
  let path     : String
  
  @discardableResult init(path: String, port: UInt16,
    callback: @escaping @Sendable (Request?, Response?, NWError?) -> Void)
  {
    self.callback = callback
    self.path     = path
    self.listener = try! NWListener(using:.tcp, on:NWEndpoint.Port(rawValue:port)!)
    listener.newConnectionHandler = {(_ connection: NWConnection) in
      connection.start(queue:.main)
      self.receive(from:connection)}
    listener.start(queue:.main)
  }
}

private extension Server {
  func receive(from connection: NWConnection) {
    connection.receive(minimumIncompleteLength:1, maximumLength:connection.maximumDatagramSize)
    { content, _, complete, error in
      if let error
        {self.callback(nil, nil, error)}
      else if let content, let request = Request(content)
        {self.respond(on:connection, request:request)}
      if !complete
        {self.receive(from:connection)}
    }
  }
  
  func respond(on connection: NWConnection, request: Request) {
    guard request.method == "GET" else {
      let response = Response(.teapot)
      callback(request, response, nil)
      connection.send(content:response.data, completion:.idempotent)
      return
    }
    
    func findFile(_ filePath: String) -> String? {
      var isDir: ObjCBool = false
      guard let foundPath = [filePath, filePath + "/index.html", filePath + "/index.htm"]
        .first(where: {FileManager.default.fileExists(atPath:$0, isDirectory:&isDir)
          ? !isDir.boolValue : false})
      else {return nil}
      return foundPath
    }
    
    guard
      let filePath = findFile(self.path + request.path),
      let response = try? Response(filePath:filePath)
    else {
      let response = Response(.notFound)
      callback(request, response, nil)
      connection.send(content:response.data, completion:.idempotent)
      return
    }
    
    callback(request, response, nil)
    connection.send(content:response.data, completion:.idempotent)
  }
}

extension URL {
  func serve(port: UInt16, callback: @escaping @Sendable (Request?, Response?, NWError?) -> Void)
    {Server(path:self.masked, port:port, callback:callback)}
}