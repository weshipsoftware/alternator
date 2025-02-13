import Foundation

// TODO: Use instances instead of statics.
// --> Watcher(path: ...).onChange({urls in ...})

class Watcher {
  nonisolated(unsafe) static var onEvent: ([URL]) -> Void = {_ in}

  static let callback: FSEventStreamCallback = { (_, _, count, paths, _, _) in
    let unsafePointer = paths.assumingMemoryBound(to:UnsafePointer<CChar>.self)
    let bufferPointer = UnsafeBufferPointer(start:unsafePointer, count:count)
    let eventUrls = Array(Set((0..<count).map {URL(pointer:bufferPointer[$0])}))
    Watcher.onEvent(eventUrls)
  }

  @discardableResult init(url: URL, onEvent: @escaping ([URL]) -> Void) {
    Self.onEvent = onEvent
    let eventStream = FSEventStreamCreate(nil, Self.callback, nil,
      [url.path() as NSString] as NSArray, UInt64(kFSEventStreamEventIdSinceNow), 1.0,
      FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))!
    FSEventStreamSetDispatchQueue(eventStream, DispatchQueue.main)
    FSEventStreamStart(eventStream)
  }
}

extension URL {
  init(pointer: UnsafePointer<Int8>)
    {self = URL(fileURLWithFileSystemRepresentation:pointer, isDirectory:false, relativeTo:nil)}
}