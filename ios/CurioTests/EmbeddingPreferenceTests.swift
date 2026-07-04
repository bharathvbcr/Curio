import XCTest
@testable import Curio

final class EmbeddingPreferenceTests: XCTestCase {

    private let backendKey = "embedding_backend"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: backendKey)
        super.tearDown()
    }

    func testDefaultIsAuto() {
        UserDefaults.standard.removeObject(forKey: backendKey)
        XCTAssertEqual(EmbeddingPreference.get(), .auto)
    }

    func testRoundTripPersistence() {
        EmbeddingPreference.set(.onDevice)
        XCTAssertEqual(EmbeddingPreference.get(), .onDevice)
        EmbeddingPreference.set(.xai)
        XCTAssertEqual(EmbeddingPreference.get(), .xai)
    }

    func testInvalidStoredValueFallsBackToAuto() {
        UserDefaults.standard.set("NOT_A_BACKEND", forKey: backendKey)
        XCTAssertEqual(EmbeddingPreference.get(), .auto)
    }
}
