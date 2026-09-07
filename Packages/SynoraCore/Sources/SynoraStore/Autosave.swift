import Foundation
import SynoraDomain

public struct AutosaveConflict: Hashable, Sendable {
  public let recordID: UUID
  public let expectedRevision: Int
  public let actualRevision: Int
  public let localRecord: DomainRecord
  public let localDocument: BlockDocument
  public let savedRecord: DomainRecord?
  public let savedDocument: BlockDocument?

  public init(
    recordID: UUID,
    expectedRevision: Int,
    actualRevision: Int,
    localRecord: DomainRecord,
    localDocument: BlockDocument,
    savedRecord: DomainRecord?,
    savedDocument: BlockDocument?
  ) {
    self.recordID = recordID
    self.expectedRevision = expectedRevision
    self.actualRevision = actualRevision
    self.localRecord = localRecord
    self.localDocument = localDocument
    self.savedRecord = savedRecord
    self.savedDocument = savedDocument
  }
}

public enum AutosaveResult: Hashable, Sendable {
  case saved(StoreReceipt)
  case conflict(AutosaveConflict)
  case failed(String)
  case cancelled
}

public actor AutosaveCoordinator {
  private struct Pending: Hashable, Sendable {
    let record: DomainRecord
    let document: BlockDocument
    let expectedRevision: Int
    let operationID: UUID
  }

  private let store: ProductStore
  private var pending: [UUID: Pending] = [:]
  private var scheduled: [UUID: Task<Void, Never>] = [:]
  private var lastResults: [UUID: AutosaveResult] = [:]

  public init(store: ProductStore) {
    self.store = store
  }

  public func schedule(
    record: DomainRecord,
    document: BlockDocument,
    expectedRevision: Int,
    operationID: UUID = UUID(),
    delayNanoseconds: UInt64 = 250_000_000
  ) {
    let pendingChange = Pending(
      record: record,
      document: document,
      expectedRevision: expectedRevision,
      operationID: operationID)
    pending[record.id] = pendingChange
    scheduled[record.id]?.cancel()
    scheduled[record.id] = Task { [weak self] in
      do {
        if delayNanoseconds > 0 {
          try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        guard !Task.isCancelled else { return }
        _ = await self?.flush(recordID: record.id).first
      } catch is CancellationError {
      } catch {
      }
    }
  }

  public func saveNow(
    record: DomainRecord,
    document: BlockDocument,
    expectedRevision: Int,
    operationID: UUID = UUID()
  ) async -> AutosaveResult {
    let pendingChange = Pending(
      record: record,
      document: document,
      expectedRevision: expectedRevision,
      operationID: operationID)
    pending[record.id] = pendingChange
    scheduled[record.id]?.cancel()
    scheduled[record.id] = nil
    return await persist(pendingChange)
  }

  public func flush(recordID: UUID? = nil) async -> [AutosaveResult] {
    let ids = recordID.map { [$0] } ?? pending.keys.sorted { $0.uuidString < $1.uuidString }
    var results: [AutosaveResult] = []
    for id in ids {
      scheduled[id]?.cancel()
      scheduled[id] = nil
      guard let change = pending[id] else { continue }
      results.append(await persist(change))
    }
    return results
  }

  public func cancel(recordID: UUID) {
    scheduled[recordID]?.cancel()
    scheduled[recordID] = nil
    pending[recordID] = nil
    lastResults[recordID] = .cancelled
  }

  public func pendingRecordIDs() -> [UUID] {
    pending.keys.sorted { $0.uuidString < $1.uuidString }
  }

  public func pendingChange(
    for recordID: UUID
  ) -> (record: DomainRecord, document: BlockDocument, expectedRevision: Int)? {
    guard let change = pending[recordID] else { return nil }
    return (change.record, change.document, change.expectedRevision)
  }

  public func result(for recordID: UUID) -> AutosaveResult? {
    lastResults[recordID]
  }

  public func stop(flushing: Bool = true) async -> [AutosaveResult] {
    if flushing { return await flush() }
    for task in scheduled.values { task.cancel() }
    scheduled.removeAll()
    pending.removeAll()
    return []
  }

  private func persist(_ change: Pending) async -> AutosaveResult {
    do {
      let receipt = try await Task.detached(priority: .userInitiated) { [store] in
        try store.save(
          record: change.record,
          document: change.document,
          expectedRevision: change.expectedRevision,
          operationID: change.operationID)
      }.value
      if pending[change.record.id] == change {
        pending[change.record.id] = nil
      }
      let result = AutosaveResult.saved(receipt)
      lastResults[change.record.id] = result
      return result
    } catch let error as RevisionError {
      let expectedRevision: Int
      let actualRevision: Int
      switch error {
      case .stale(let expected, let actual):
        expectedRevision = expected
        actualRevision = actual
      }
      let savedRecord = try? store.record(id: change.record.id)
      let savedDocument = try? store.document(recordID: change.record.id)
      let conflict = AutosaveConflict(
        recordID: change.record.id,
        expectedRevision: expectedRevision,
        actualRevision: actualRevision,
        localRecord: change.record,
        localDocument: change.document,
        savedRecord: savedRecord,
        savedDocument: savedDocument)
      let result = AutosaveResult.conflict(conflict)
      lastResults[change.record.id] = result
      return result
    } catch is CancellationError {
      let result = AutosaveResult.cancelled
      lastResults[change.record.id] = result
      return result
    } catch {
      let result = AutosaveResult.failed(String(describing: error))
      lastResults[change.record.id] = result
      return result
    }
  }
}
