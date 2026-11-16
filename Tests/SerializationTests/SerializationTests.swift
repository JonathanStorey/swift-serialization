import Testing
@testable import Serialization

@Suite struct SerializationTests {
    @Test func moduleLoads() {
        #expect(Bool(true))
    }
}
