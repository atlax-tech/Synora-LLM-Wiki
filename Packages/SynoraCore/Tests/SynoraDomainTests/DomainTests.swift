import Foundation
import Testing

@testable import SynoraDomain

@Test
func fixedIDsAndRevisionAreDeterministic() throws {
  let first = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
  let second = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
  let generator = FixedIDGenerator([first, second])
  #expect(generator.next() == first)
  #expect(generator.next() == second)
  #expect(try Revision.next(after: 0, expected: 0) == 1)
  #expect(throws: RevisionError.stale(expected: 0, actual: 1)) {
    try Revision.next(after: 1, expected: 0)
  }
}

@Test
func operationHashUsesCanonicalBytes() {
  let id = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
  let entity = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
  let timestamp = Date(timeIntervalSince1970: 1)
  let left = Operation(
    id: id,
    transactionID: 1,
    sequence: 1,
    entityID: entity,
    entityRevision: 1,
    kind: "record.save",
    payload: Data("{}".utf8),
    timestamp: timestamp,
    previousHash: nil
  )
  let right = Operation(
    id: id,
    transactionID: 1,
    sequence: 1,
    entityID: entity,
    entityRevision: 1,
    kind: "record.save",
    payload: Data("{}".utf8),
    timestamp: timestamp,
    previousHash: nil
  )
  #expect(left.canonicalBytes == right.canonicalBytes)
  #expect(left.hash == right.hash)
}
