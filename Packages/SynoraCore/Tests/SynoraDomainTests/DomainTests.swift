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
func uuidGeneratorProducesVersionFourUniqueIDs() {
  let generator = UUIDGenerator()
  let ids = (0..<10_000).map { _ in generator.next() }
  #expect(Set(ids).count == ids.count)
  #expect(
    ids.allSatisfy { uuid in
      withUnsafeBytes(of: uuid.uuid) { bytes in
        bytes[6] >> 4 == 4 && bytes[8] & 0xC0 == 0x80
      }
    })
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
  #expect(
    String(decoding: left.canonicalBytes, as: UTF8.self)
      == "{\"entityID\":\"00000000-0000-4000-8000-000000000002\",\"entityRevision\":1,\"id\":\"00000000-0000-4000-8000-000000000001\",\"kind\":\"record.save\",\"payload\":\"e30=\",\"previousHash\":null,\"sequence\":1,\"timestamp\":1,\"transactionID\":1}"
  )
  #expect(left.hash == "3f23cfd87d3fb1d6333e02fde4f1b7eb8ef9b18997d0b05b6179128ec899ef86")
}
