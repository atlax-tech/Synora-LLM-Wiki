import Foundation

#if canImport(os)
import os
#endif

public enum EditorTelemetry {
  #if canImport(os)
  private static let log = OSLog(subsystem: "tech.atlax.SynoraWiki", category: "Editor")

  public static func begin(_ name: StaticString) -> OSSignpostID {
    let id = OSSignpostID(log: log)
    os_signpost(.begin, log: log, name: name, signpostID: id)
    return id
  }

  public static func end(_ name: StaticString, _ id: OSSignpostID) {
    os_signpost(.end, log: log, name: name, signpostID: id)
  }
  #else
  public static func begin(_ name: StaticString) -> UInt64 { _ = name; return 0 }
  public static func end(_ name: StaticString, _ id: UInt64) { _ = name; _ = id }
  #endif
}
