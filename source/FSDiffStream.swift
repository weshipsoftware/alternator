import Foundation

struct FSDiffStream {
  let callback: FSEventStreamCallback = { (_, _, numEvents, eventPaths, _, _) in
    let buffer = UnsafeBufferPointer(
      start: eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self),
      count: numEvents)

    let diffs = (0..<numEvents)
      .map { URL(
        fileURLWithFileSystemRepresentation: buffer[$0],
        isDirectory: false,
        relativeTo: nil) }
      .unique
      .filter {$0.lastPathComponent != ".DS_Store"}

    guard !diffs
      .filter({
        guard Project.srcContainsTgt else {return true}
        return !$0.absoluteString.contains(Project.tgt!.absoluteString) })
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