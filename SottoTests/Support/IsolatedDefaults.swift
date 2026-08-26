import Foundation
import XCTest

extension XCTestCase {
    /// A `UserDefaults` domain private to one test and removed when it ends, so
    /// a test that writes a preference never touches the developer's settings.
    func isolatedDefaults(_ label: String = #function) -> UserDefaults {
        let suite = "\(type(of: self)).\(label).\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }
}
