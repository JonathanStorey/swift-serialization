import Testing
@testable import Versioning

private struct Email: Codable, Equatable {
    var address: String
    var label: String?
}

private struct Contact: Codable, Equatable {
    var name: String
    var nickname: String?
    var emails: [Email]
}

private struct Settings: Codable {
    var theme: String
    var fontSize: Int
    var tags: [String]
}

@Suite struct JSONDifferenceAsTypeTests {
    /// The example in the README.
    @Test func readmeExample() throws {
        let stored: JSONRepresentation = ["theme": "dark", "fontSize": 14, "tags": ["a"], "legacy": true]
        let current = try JSONRepresentation(Settings(theme: "light", fontSize: 14, tags: ["a"]))
        #expect(current.difference(from: stored).description == """
            ~ $.theme: "dark" → "light"
            - $.legacy: true
            """)
        #expect(try current.difference(from: stored, as: Settings.self).description == #"~ $.theme: "dark" → "light""#)
    }

    @Test func missingAndNullOptionalsAreTheSame() throws {
        let stored: JSONRepresentation = ["name": "Ada", "nickname": nil, "emails": [["address": "a@x", "label": nil]]]
        let current: JSONRepresentation = ["name": "Ada", "emails": [["address": "a@x"]]]
        #expect(!current.difference(from: stored).isEmpty)
        #expect(try current.difference(from: stored, as: Contact.self).isEmpty)
    }

    @Test func undeclaredKeysAreIgnored() throws {
        let stored: JSONRepresentation = ["name": "Ada", "emails": [], "serverVersion": 41]
        let current: JSONRepresentation = ["name": "Ada", "emails": [], "serverVersion": 42, "debug": true]
        #expect(current.difference(from: stored).count == 3)
        #expect(try current.difference(from: stored, as: Contact.self).isEmpty)
    }

    @Test func visibleChangesAreKept() throws {
        let stored: JSONRepresentation = ["name": "Ada", "emails": [["address": "a@x", "extra": 1]], "extra": 1]
        let current: JSONRepresentation = ["name": "Ada", "nickname": "A", "emails": [["address": "b@x"]]]
        let difference = try current.difference(from: stored, as: Contact.self)
        #expect(difference.description == """
            ~ $.emails[0].address: "a@x" → "b@x"
            + $.nickname: "A"
            """)
    }

    @Test func nullStandingForMissingIsReplaced() throws {
        let stored: JSONRepresentation = ["name": "Ada", "nickname": nil, "emails": []]
        let current: JSONRepresentation = ["name": "Ada", "nickname": "A", "emails": []]
        let difference = try current.difference(from: stored, as: Contact.self)
        #expect(difference.description == #"~ $.nickname: null → "A""#)
    }

    /// Every pair of these values must give a difference that, applied in
    /// either direction, decodes to the same contact as its target.
    @Test func appliedDifferenceDecodesTheSame() throws {
        let values: [JSONRepresentation] = [
            ["name": "Ada", "emails": []],
            ["name": "Ada", "nickname": nil, "emails": [], "x": 1],
            ["name": "Ada", "nickname": "A", "emails": [["address": "a@x"]]],
            ["name": "Ada", "nickname": "B", "emails": [["address": "a@x", "label": nil, "y": 2], ["address": "b@x"]]],
            ["x": [1], "name": "Bo", "emails": [["address": "b@x", "label": "work"], ["address": "a@x"]]],
            ["name": "Bo", "emails": [["address": "b@x", "label": "home"]], "nickname": "A"],
        ]
        for stored in values {
            for current in values {
                let difference = try current.difference(from: stored, as: Contact.self)
                let forward = try #require(stored.applying(difference), "\(stored) → \(current)\n\(difference)")
                #expect(try forward.decode(Contact.self) == current.decode(Contact.self), "\(stored) → \(current)\n\(difference)")
                let backward = try #require(current.applying(difference.inverted()), "\(current) ← \(stored)\n\(difference)")
                #expect(try backward.decode(Contact.self) == stored.decode(Contact.self), "\(current) ← \(stored)\n\(difference)")
            }
        }
    }

    @Test func throwsForTypesWithoutASchema() {
        let json: JSONRepresentation = ["a": 1]
        #expect(throws: DecodingError.self) { try json.difference(from: json, as: [Int: Int].self) }
    }
}
