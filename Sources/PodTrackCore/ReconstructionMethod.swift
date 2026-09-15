import Foundation

public enum ReconstructionMethod: String, CaseIterable, Codable, Hashable, Sendable {
    case improved = "Improved"
    case old = "Old"

    public func analyze(_ run: RunSession) throws -> AnalysisResult {
        switch self {
        case .improved: return try ImprovedReconstruction.analyze(run)
        case .old: return try AnalysisPipeline.analyze(run)
        }
    }
}
