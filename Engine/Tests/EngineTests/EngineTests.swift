import Testing
@testable import Engine

@Test func engineHasVersion() {
    #expect(!Engine.version.isEmpty)
}
