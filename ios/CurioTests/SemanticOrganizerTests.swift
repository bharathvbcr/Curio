import XCTest
@testable import Curio

/// Pure tests for the embedding-driven auto-organisation engine.
final class SemanticOrganizerTests: XCTestCase {

    private let aDir: [Float] = [1, 0, 0]
    private let bDir: [Float] = [0, 1, 0]

    private func near(_ base: [Float], jitter: Float) -> [Float] {
        [base[0] + jitter, base[1] + jitter / 2, base[2]]
    }

    func testHighSimilarityAutoFiles() {
        let plan = SemanticOrganizer.buildPlan(
            unfiled: [("x", aDir)],
            spaceCentroids: ["spaceA": aDir, "spaceB": bDir]
        )
        XCTAssertEqual(plan.autoFile.count, 1)
        XCTAssertEqual(plan.autoFile.first?.bookmarkId, "x")
        XCTAssertEqual(plan.autoFile.first?.spaceId, "spaceA")
        XCTAssertTrue(plan.suggestions.isEmpty)
    }

    func testMediumSimilarityBecomesSuggestion() {
        let medium: [Float] = [1, 0.3, 1.2]
        let plan = SemanticOrganizer.buildPlan(
            unfiled: [("m", medium)],
            spaceCentroids: ["spaceA": aDir, "spaceB": bDir]
        )
        XCTAssertTrue(plan.suggestions.contains { $0.bookmarkId == "m" && $0.spaceId == "spaceA" })
        XCTAssertFalse(plan.autoFile.contains { $0.bookmarkId == "m" })
    }

    func testPairFormsCluster() {
        let cDir: [Float] = [0, 0, 1]
        let plan = SemanticOrganizer.buildPlan(
            unfiled: [("p0", near(cDir, 0)), ("p1", near(cDir, 0.001))],
            spaceCentroids: [:]
        )
        XCTAssertEqual(plan.clusters.count, 1)
        XCTAssertEqual(plan.clusters.first?.bookmarkIds.count, 2)
    }

    func testTransitiveClustering() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0.85, 0.53, 0]
        let c: [Float] = [0.3, 0.95, 0]
        XCTAssertGreaterThanOrEqual(VectorSearch.cosineSimilarity(a, b), SemanticOrganizer.clusterThreshold)
        XCTAssertGreaterThanOrEqual(VectorSearch.cosineSimilarity(b, c), SemanticOrganizer.clusterThreshold)
        XCTAssertLessThan(VectorSearch.cosineSimilarity(a, c), SemanticOrganizer.clusterThreshold)

        let plan = SemanticOrganizer.buildPlan(
            unfiled: [("a", a), ("b", b), ("c", c)],
            spaceCentroids: [:]
        )
        XCTAssertEqual(plan.clusters.count, 1)
        XCTAssertEqual(Set(plan.clusters.first?.bookmarkIds ?? []), Set(["a", "b", "c"]))
    }

    func testTieBreakPrefersLargerSpace() {
        let query: [Float] = [1, 0.1, 0]
        let centroid: [Float] = [1, 0, 0]
        let plan = SemanticOrganizer.buildPlan(
            unfiled: [("x", query)],
            spaceCentroids: ["small": centroid, "large": centroid],
            spaceMemberCounts: ["small": 2, "large": 20]
        )
        XCTAssertEqual(plan.autoFile.first?.spaceId, "large")
    }

    func testLoneLeftoverDoesNotCluster() {
        let cDir: [Float] = [0, 0, 1]
        let plan = SemanticOrganizer.buildPlan(
            unfiled: [("lonely", cDir)],
            spaceCentroids: ["spaceA": aDir]
        )
        XCTAssertTrue(plan.clusters.isEmpty)
        XCTAssertTrue(plan.autoFile.isEmpty)
        XCTAssertTrue(plan.suggestions.isEmpty)
    }

    func testNoExistingSpacesClustersAllLeftovers() {
        let cDir: [Float] = [0, 0, 1]
        let unfiled = (0..<4).map { ("c\($0)", near(cDir, Float($0) * 0.001)) }
        let plan = SemanticOrganizer.buildPlan(unfiled: unfiled, spaceCentroids: [:])
        XCTAssertEqual(plan.clusters.count, 1)
        XCTAssertEqual(plan.clusters.first?.bookmarkIds.count, 4)
    }

    func testDifferentDimensionsNeverCrossCluster() {
        let dim3: [Float] = [0, 0, 1]
        let dim4a: [Float] = [0, 0, 1, 0]
        let dim4b: [Float] = [0, 0, 0.99, 0.01]
        let plan = SemanticOrganizer.buildPlan(
            unfiled: [
                ("a", near(dim3, 0)),
                ("b", near(dim3, 0.001)),
                ("c", dim4a),
                ("d", dim4b)
            ],
            spaceCentroids: [:]
        )
        XCTAssertEqual(plan.clusters.count, 2)
        XCTAssertEqual(plan.clusters.map { $0.bookmarkIds.count }.sorted(), [2, 2])
    }

    func testCentroidMatchSkipsMismatchedDimensions() {
        let query: [Float] = [1, 0, 0]
        let wrongDim: [Float] = [1, 0, 0, 0]
        let plan = SemanticOrganizer.buildPlan(
            unfiled: [("x", query)],
            spaceCentroids: ["wrong": wrongDim]
        )
        XCTAssertTrue(plan.autoFile.isEmpty)
        XCTAssertTrue(plan.suggestions.isEmpty)
        XCTAssertTrue(plan.clusters.isEmpty)
    }

    func testZeroNormEmbeddingIsIgnored() {
        let zero: [Float] = [0, 0, 0]
        let plan = SemanticOrganizer.buildPlan(
            unfiled: [("z", zero), ("a", aDir)],
            spaceCentroids: ["spaceA": aDir]
        )
        XCTAssertEqual(plan.autoFile.count, 1)
        XCTAssertEqual(plan.autoFile.first?.bookmarkId, "a")
        XCTAssertTrue(plan.suggestions.isEmpty)
        XCTAssertTrue(plan.clusters.isEmpty)
    }

    func testOversizedBucketSkipsClustering() {
        let cDir: [Float] = [0, 0, 1]
        let unfiled = (0..<(SemanticOrganizer.maxClusterBucketSize + 1)).map { i in
            ("c\(i)", near(cDir, Float(i) * 0.0001))
        }
        let plan = SemanticOrganizer.buildPlan(unfiled: unfiled, spaceCentroids: [:])
        XCTAssertTrue(plan.clusters.isEmpty)
    }
}
