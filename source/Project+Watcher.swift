import Foundation

extension Project {
  static func watch() {
    let callback: FSEventStreamCallback = { (_, _, count, paths, _, _) in
      let buffer = UnsafeBufferPointer(
        start: paths.assumingMemoryBound(to: UnsafePointer<CChar>.self),
        count: count)
      let diffs = (0..<count)
        .map { URL(fileURLWithFileSystemRepresentation: buffer[$0],
                   isDirectory: false, relativeTo: nil) }
        .reduce(into: Set<URL>(), { (result, x) in result.insert(x) })
        .filter {
          guard $0.lastPathComponent != ".DS_Store"     else { return false }
          guard Project.source.encloses(Project.target) else { return true  }
          return !Project.target.encloses($0) }
      guard !diffs.isEmpty else { return }
      Project.build()
    }

    let stream: FSEventStreamRef = FSEventStreamCreate(
      nil, callback, nil, [source.rawPath as NSString] as NSArray,
      UInt64(kFSEventStreamEventIdSinceNow), 1.0,
      FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
    )!

    FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
    FSEventStreamStart(stream)
    print("[watch] watching \(source.description) for changes")
  }
}
