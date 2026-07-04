import Foundation

/// Embedding-driven auto-organisation engine (pure Foundation, unit-testable).
///
/// Ports `object SemanticOrganizer` from `data/embedding/SemanticOrganizer.kt`.
enum SemanticOrganizer {

    /// Cosine at/above which an unfiled card is filed into the nearest Space automatically.
    static let autoFileThreshold: Float = 0.68

    /// Cosine at/above which (but below `autoFileThreshold`) we only *suggest* the Space.
    static let suggestThreshold: Float = 0.50

    /// Minimum mutual cosine for two leftover cards to share a new cluster.
    static let clusterThreshold: Float = 0.62

    /// A cluster smaller than this isn't worth its own Space.
    static let minClusterSize = 2

    /// Skip connected-components clustering above this bucket size (O(n²) pairwise graph).
    static let maxClusterBucketSize = 200

    struct Assignment: Equatable, Sendable {
        let bookmarkId: String
        let spaceId: String
        let score: Float
    }

    struct Cluster: Equatable, Sendable {
        let bookmarkIds: [String]
        let centroid: [Float]
        let cohesion: Float
    }

    struct Plan: Equatable, Sendable {
        let autoFile: [Assignment]
        let suggestions: [Assignment]
        let clusters: [Cluster]
    }

    static func buildPlan(
        unfiled: [(String, [Float])],
        spaceCentroids: [String: [Float]],
        spaceMemberCounts: [String: Int] = [:]
    ) -> Plan {
        var autoFile: [Assignment] = []
        var suggestions: [Assignment] = []
        var leftovers: [(String, [Float])] = []

        for (id, emb) in unfiled {
            // Empty or zero-norm vectors can't match centroids or form clusters — skip them.
            if emb.isEmpty || VectorSearch.normalizeL2(emb) == nil { continue }
            let best = spaceCentroids
                .filter { $0.value.count == emb.count }
                .map { spaceId, centroid in
                (
                    spaceId,
                    VectorSearch.cosineSimilarity(emb, centroid),
                    spaceMemberCounts[spaceId] ?? 0
                )
            }.max { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
                return lhs.0 > rhs.0
            }

            guard let best else {
                leftovers.append((id, emb))
                continue
            }
            if best.1 < suggestThreshold {
                leftovers.append((id, emb))
            } else if best.1 >= autoFileThreshold {
                autoFile.append(Assignment(bookmarkId: id, spaceId: best.0, score: best.1))
            } else {
                suggestions.append(Assignment(bookmarkId: id, spaceId: best.0, score: best.1))
            }
        }

        return Plan(autoFile: autoFile, suggestions: suggestions, clusters: clusterLeftovers(leftovers))
    }

    /// Connected-components clustering on the pairwise similarity graph (transitive groups).
    private static func clusterLeftovers(_ leftovers: [(String, [Float])]) -> [Cluster] {
        if leftovers.count < minClusterSize { return [] }
        return Dictionary(grouping: leftovers, by: { $0.1.count })
            .flatMap { clusterLeftoversSameDim($0.value) }
            .sorted { ($0.bookmarkIds.min() ?? "") < ($1.bookmarkIds.min() ?? "") }
    }

    /// Connected-components on one dimension bucket; pre-normalises for faster dot-product checks.
    private static func clusterLeftoversSameDim(_ leftovers: [(String, [Float])]) -> [Cluster] {
        let n = leftovers.count
        if n < minClusterSize || n > maxClusterBucketSize { return [] }

        let normalized = leftovers.map { VectorSearch.normalizeL2($0.1) }
        var parent = Array(0..<n)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r {
                parent[r] = parent[parent[r]]
                r = parent[r]
            }
            return r
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a)
            let rb = find(b)
            if ra != rb { parent[rb] = ra }
        }

        for i in 0..<n {
            guard let ni = normalized[i] else { continue }
            for j in (i + 1)..<n {
                guard let nj = normalized[j] else { continue }
                if VectorSearch.dotProduct(ni, nj) >= clusterThreshold {
                    union(i, j)
                }
            }
        }

        var groups: [Int: [Int]] = [:]
        for i in 0..<n {
            groups[find(i), default: []].append(i)
        }

        return groups.values
            .filter { $0.count >= minClusterSize }
            .compactMap { indices -> Cluster? in
                let members = indices.map { leftovers[$0] }
                guard let centroid = meanVector(members.map { $0.1 }) else { return nil }
                let cohesion = Float(
                    members.map { VectorSearch.cosineSimilarity(centroid, $0.1) }
                        .reduce(0, +) / Float(members.count)
                )
                return Cluster(
                    bookmarkIds: members.map { $0.0 },
                    centroid: centroid,
                    cohesion: cohesion
                )
            }
    }

    static func meanVector(_ vectors: [[Float]]) -> [Float]? {
        guard let first = vectors.first, !first.isEmpty else { return nil }
        let dim = first.count
        if vectors.contains(where: { $0.count != dim }) { return nil }
        var acc = [Float](repeating: 0, count: dim)
        for v in vectors {
            for j in 0..<dim { acc[j] += v[j] }
        }
        let count = Float(vectors.count)
        return acc.map { $0 / count }
    }
}
