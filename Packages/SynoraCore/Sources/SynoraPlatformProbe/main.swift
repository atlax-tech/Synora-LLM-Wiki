import Foundation
import SynoraPlatform

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(PlatformReport.current)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([0x0A]))
