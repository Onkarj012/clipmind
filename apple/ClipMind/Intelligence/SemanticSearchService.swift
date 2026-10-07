import Foundation

struct ScoredItemID: Equatable, Sendable {
    let itemID: String
    let score: Double
}

struct SemanticSearchService: Sendable {
    let generator: EmbeddingGenerator

    func embedQuery(_ text: String) async throws -> [Float] {
        try await generator.generateEmbedding(for: text)
    }

    static func rank(
        queryEmbedding: [Float],
        candidates: [(itemID: String, vector: [Float])]
    ) -> [ScoredItemID] {
        candidates
            .map { candidate in
                ScoredItemID(
                    itemID: candidate.itemID,
                    score: Double(VectorMath.cosineSimilarity(queryEmbedding, candidate.vector))
                )
            }
            .sorted { $0.score > $1.score }
    }

    static func mergeHybridResults(
        ftsRanked: [ScoredItemID],
        semanticRanked: [ScoredItemID],
        limit: Int,
        reciprocalRankConstant: Int = 60
    ) -> [String] {
        var scores: [String: Double] = [:]

        for (rank, item) in ftsRanked.enumerated() {
            scores[item.itemID, default: 0] += 1.0 / Double(reciprocalRankConstant + rank + 1)
        }

        for (rank, item) in semanticRanked.enumerated() {
            scores[item.itemID, default: 0] += 1.0 / Double(reciprocalRankConstant + rank + 1)
        }

        return scores
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(limit)
            .map(\.key)
    }
}
