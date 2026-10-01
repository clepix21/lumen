import Testing
@testable import LumenCore

@Test func coreModuleLoads() {
    #expect(LumenCore.self == LumenCore.self)
}
