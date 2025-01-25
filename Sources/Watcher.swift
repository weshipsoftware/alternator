import Foundation

class Watcher {
  @discardableResult init(_ url: URL, callback: @escaping FSEventStreamCallback) {
    let stream = FSEventStreamCreate(
      nil, callback, nil, [url.path() as NSString] as NSArray,
      UInt64(kFSEventStreamEventIdSinceNow), 1.0,
      FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))!
    
    FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
    FSEventStreamStart(stream)
  }
  
  static func parseEvents(_ numEvents: Int, _ eventPaths: UnsafeMutableRawPointer) -> [URL] {
    let bufferPathsStart = eventPaths.assumingMemoryBound(to:UnsafePointer<CChar>.self)
    let bufferPaths      = UnsafeBufferPointer(start:bufferPathsStart, count:numEvents)
    
    let urls = (0..<numEvents).map
      {URL(fileURLWithFileSystemRepresentation:bufferPaths[$0], isDirectory:false, relativeTo:nil)}
    
    return Array(Set(urls))
  }
}

extension URL {
  func watch(callback: @escaping FSEventStreamCallback)
    {Watcher(self, callback:callback)}
}