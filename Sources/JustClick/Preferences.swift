import Foundation

enum Preferences {
    private static let suite: String? = ProcessInfo.processInfo.environment["JUSTCLICK_DATA_DIR"] == nil ? nil : "local.justclick.test." + UUID().uuidString
    static let defaults: UserDefaults = suite.flatMap { UserDefaults(suiteName:$0) } ?? .standard
    static func cleanUpTestDomain() { if let suite { defaults.removePersistentDomain(forName:suite) } }
}
