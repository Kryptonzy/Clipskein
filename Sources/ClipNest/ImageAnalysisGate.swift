import Foundation

actor ImageAnalysisGate {
  nonisolated let maximumConcurrent: Int

  private var activeCount = 0
  private var waiters: [(
    id: UUID,
    continuation: CheckedContinuation<Bool, Never>
  )] = []

  init(maximumConcurrent: Int = 2) {
    self.maximumConcurrent = max(1, maximumConcurrent)
  }

  func run<T: Sendable>(
    _ operation: @escaping @Sendable () async -> T
  ) async -> T? {
    guard await acquire() else { return nil }
    defer { release() }
    guard !Task.isCancelled else { return nil }
    return await operation()
  }

  private func acquire() async -> Bool {
    guard !Task.isCancelled else { return false }
    if activeCount < maximumConcurrent {
      activeCount += 1
      return true
    }
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled {
          continuation.resume(returning: false)
        } else {
          waiters.append((id, continuation))
        }
      }
    } onCancel: {
      Task { await self.cancelWaiter(id: id) }
    }
  }

  private func cancelWaiter(id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
    let waiter = waiters.remove(at: index)
    waiter.continuation.resume(returning: false)
  }

  private func release() {
    if waiters.isEmpty {
      activeCount = max(0, activeCount - 1)
      return
    }
    let waiter = waiters.removeFirst()
    waiter.continuation.resume(returning: true)
  }
}
