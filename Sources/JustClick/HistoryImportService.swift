import Foundation
import JustClickCore

enum HistoryImportService {
    static func discover(to output: URL) async throws -> HistoryDiscoveryReport {
        try await Task.detached(priority:.utility) {
            let fm = FileManager.default
            guard let script = Bundle.main.url(forResource:"discover",withExtension:"py",subdirectory:"history"),
                  let python = ["/opt/homebrew/bin/python3","/usr/local/bin/python3","/usr/bin/python3"].first(where:fm.isExecutableFile(atPath:)),
                  let codex = ["/opt/homebrew/bin/codex","/usr/local/bin/codex"].first(where:fm.isExecutableFile(atPath:)) else {
                throw LibraryError.invalid("Python 3 / Codex CLI is unavailable")
            }
            let process = Process(); process.executableURL = URL(fileURLWithPath:python)
            process.arguments = [script.path,"--codex",codex,"--output",output.path,"--max-threads","500"]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw LibraryError.invalid("Codex history read failed; existing library preserved") }
            let data = try Data(contentsOf:output)
            guard data.count <= 2_000_000 else { throw LibraryError.invalid("History report is too large") }
            return try JSONDecoder().decode(HistoryDiscoveryReport.self,from:data)
        }.value
    }
}
