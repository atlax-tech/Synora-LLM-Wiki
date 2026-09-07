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

@Test
func blockDocumentPreservesIdentityOrderingAndUnknownFields() throws {
  let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000010")!
  let firstID = UUID(uuidString: "00000000-0000-4000-8000-000000000011")!
  let secondID = UUID(uuidString: "00000000-0000-4000-8000-000000000012")!
  let first = Block(
    id: firstID, recordID: recordID, position: 0, text: "中文🙂",
    type: .bulletedList, unknownFields: ["future": .object(["enabled": .bool(true)])])
  let second = Block(
    id: secondID, recordID: recordID, position: 1, text: "子项", parentID: firstID,
    type: .paragraph)
  let document = try BlockDocument(recordID: recordID, blocks: [first, second])

  #expect(document.children().map(\.id) == [firstID])
  #expect(document.descendants(of: firstID).map(\.id) == [secondID])
  let encoded = try JSONEncoder().encode(document)
  let decoded = try JSONDecoder().decode(BlockDocument.self, from: encoded)
  #expect(decoded == document)
}

@Test
func blockDocumentRejectsInvalidParentsAndCycles() throws {
  let recordID = UUID()
  let parentID = UUID()
  let childID = UUID()
  #expect(throws: BlockTreeError.invalidChild(childID)) {
    try BlockDocument(
      recordID: recordID,
      blocks: [
        Block(id: parentID, recordID: recordID, position: 0, text: "plain"),
        Block(id: childID, recordID: recordID, position: 1, text: "child", parentID: parentID),
      ])
  }
  #expect(throws: BlockTreeError.missingParent(parentID)) {
    try BlockDocument(
      recordID: recordID,
      blocks: [Block(id: childID, recordID: recordID, position: 0, text: "child", parentID: parentID)])
  }
}

@Test
func legacyBlockPayloadDecodesWithParagraphDefaults() throws {
  let id = UUID(uuidString: "00000000-0000-4000-8000-000000000020")!
  let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000021")!
  let data = Data("{\"id\":\"\(id.uuidString)\",\"recordID\":\"\(recordID.uuidString)\",\"position\":2,\"text\":\"legacy\",\"revision\":3}".utf8)
  let block = try JSONDecoder().decode(Block.self, from: data)
  #expect(block.type == .paragraph)
  #expect(block.orderKey == 2048)
}
