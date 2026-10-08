import Foundation
import Testing
@testable import Xu

@Test func appModuleLoads() {
    #expect(Bundle.main.bundleIdentifier != nil)
}
