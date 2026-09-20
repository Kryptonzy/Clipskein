import Darwin
import Foundation

/// A process-scoped advisory lock that prevents multiple ClipNest instances from
/// registering the same global shortcuts or monitoring the same pasteboard.
final class SingleInstanceLock {
  private static let ownershipLock = NSLock()
  nonisolated(unsafe) private static var locallyHeldPaths = Set<String>()

  private var fileDescriptor: Int32
  private let lockPath: String

  private init(fileDescriptor: Int32, lockPath: String) {
    self.fileDescriptor = fileDescriptor
    self.lockPath = lockPath
  }

  static func acquire(at lockURL: URL) -> SingleInstanceLock? {
    let lockPath = lockURL.standardizedFileURL.path
    ownershipLock.lock()
    let claimedLocally = locallyHeldPaths.insert(lockPath).inserted
    ownershipLock.unlock()
    guard claimedLocally else { return nil }

    var shouldReleaseLocalClaim = true
    defer {
      if shouldReleaseLocalClaim {
        ownershipLock.lock()
        locallyHeldPaths.remove(lockPath)
        ownershipLock.unlock()
      }
    }

    let directoryURL = lockURL.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    } catch {
      return nil
    }

    let descriptor = lockURL.path.withCString {
      Darwin.open($0, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
    }
    guard descriptor >= 0 else { return nil }

    guard Darwin.lockf(descriptor, F_TLOCK, 0) == 0 else {
      Darwin.close(descriptor)
      return nil
    }

    shouldReleaseLocalClaim = false
    return SingleInstanceLock(fileDescriptor: descriptor, lockPath: lockPath)
  }

  static func acquireForCurrentUser() -> SingleInstanceLock? {
    guard
      let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else { return nil }

    let lockURL =
      applicationSupport
      .appendingPathComponent("ClipNest", isDirectory: true)
      .appendingPathComponent("instance.lock", isDirectory: false)
    return acquire(at: lockURL)
  }

  func release() {
    guard fileDescriptor >= 0 else { return }
    _ = Darwin.lockf(fileDescriptor, F_ULOCK, 0)
    Darwin.close(fileDescriptor)
    fileDescriptor = -1
    Self.ownershipLock.lock()
    Self.locallyHeldPaths.remove(lockPath)
    Self.ownershipLock.unlock()
  }

  deinit {
    release()
  }
}
