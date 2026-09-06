import Foundation

enum RecordListProjection {
  static func filterAndGroup(records: [Record], query: String) -> [RecordGroup] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    let filtered =
      records
      .filter { record in
        guard !normalizedQuery.isEmpty else { return true }
        return record.title.localizedLowercase.contains(normalizedQuery)
          || record.summary.localizedLowercase.contains(normalizedQuery)
      }
      .sorted {
        if $0.modifiedAt != $1.modifiedAt {
          return $0.modifiedAt > $1.modifiedAt
        }
        return $0.id.uuidString < $1.id.uuidString
      }

    let calendar = Calendar(identifier: .gregorian)
    let grouped = Dictionary(grouping: filtered) { record in
      let components = calendar.dateComponents([.year, .month], from: record.modifiedAt)
      return RecordMonth(year: components.year ?? 0, month: components.month ?? 0)
    }

    return grouped.keys.sorted(by: >).map { month in
      RecordGroup(month: month, records: grouped[month] ?? [])
    }
  }
}
