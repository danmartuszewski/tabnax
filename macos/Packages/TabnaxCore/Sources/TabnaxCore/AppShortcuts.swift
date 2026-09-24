import Foundation

public struct AppAssignment: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var bundleID: String
    public var name: String
    public var path: String
    public var letter: String
    public var targetID: TargetID { TargetID(process: id) }
    public init(id: UUID = UUID(), bundleID: String, name: String, path: String, letter: String) {
        self.id = id; self.bundleID = bundleID; self.name = name; self.path = path; self.letter = letter
    }
}

public struct AppShortcutPreferences: Codable, Equatable, Sendable {
    public var enabled = false
    public var launchClosedApps = false
    public var assignments: [AppAssignment] = []
    public init() {}
    /// Under `.pairs`, every alphabet letter (not just the overflow key) prefixes real
    /// two-letter pool codes, so a single-letter app address on any of those letters would
    /// exact-match before the user can type the second letter, hiding every window/tab whose
    /// code starts with it. Only letters outside the alphabet are safe under `.pairs`.
    /// Otherwise the only letter that's actually off-limits is the hidden overflow filler
    /// (see `AddressBook.extended(_:)`) — every letter the user configured, including
    /// what used to be treated as "the last one", is fair game for a fixed app letter.
    public static func reservesPoolAddress(_ letter: String, alphabet: String, policy: AssignmentPolicy) -> Bool {
        policy == .pairs ? alphabet.contains(letter) : letter == AddressBook.overflowLetter(alphabet: alphabet, policy: policy)
    }
    public func validate(alphabet: String, policy: AssignmentPolicy = .stable) throws {
        guard Set(assignments.map(\.id)).count == assignments.count,
              Set(assignments.map(\.bundleID)).count == assignments.count else {
            throw SettingsError.invalid("Each application can have one fixed letter.")
        }
        guard Set(assignments.map(\.letter)).count == assignments.count else {
            throw SettingsError.invalid("That letter already belongs to another app. Choose a different letter.")
        }
        for app in assignments {
            guard !app.bundleID.isEmpty, !app.name.isEmpty, app.path.hasPrefix("/"),
                  app.letter.utf8.count == 1, app.letter.utf8.allSatisfy({ (97...122).contains($0) }) else {
                throw SettingsError.invalid("Choose an application and one letter A–Z.")
            }
            if enabled && Self.reservesPoolAddress(app.letter, alphabet: alphabet, policy: policy) {
                throw SettingsError.invalid(policy == .pairs
                    ? "\(app.letter.uppercased()) starts two-letter addresses under Pairs assignment. Choose a letter outside \(alphabet.uppercased())."
                    : "\(app.letter.uppercased()) is reserved to keep every address prefix-free. Choose a different app letter.")
            }
        }
    }
    public func assignment(for target: Target) -> AppAssignment? {
        guard enabled else { return nil }
        return assignments.first { $0.bundleID == target.bundleID }
    }
}
