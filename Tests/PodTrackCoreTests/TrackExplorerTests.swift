import XCTest
@testable import PodTrackCore

final class TrackExplorerTests: XCTestCase {
    func testHeightRangeSupportsEqualHeightEndpoints() throws {
        let slopes = [-Double.pi/4,-Double.pi/4,Double.pi/4,Double.pi/4]
        let signals = slopes.enumerated().map { i,slope in
            ProcessedSample(time:Double(i),verticalUserAcceleration:0,tangentialUserAcceleration:0,slope:slope,
                            heading:0,bank:0,turnRate:0,supportProxyG:1,accelerationMagnitude:0,isQuiet:false)
        }
        let estimate = try TrackReconstructor.reconstruct(signals:signals,speeds:[1,1,1,1],verticalDrop:0.6)
        XCTAssertEqual(estimate.points.map { $0.position.z }.min()!,0,accuracy:1e-9)
        XCTAssertEqual(estimate.points.map { $0.position.z }.max()!,0.6,accuracy:1e-9)
        XCTAssertEqual(estimate.points.first!.position.z,estimate.points.last!.position.z,accuracy:1e-9)
        XCTAssertEqual(estimate.points.last!.position.z,0.6,accuracy:1e-9)
        XCTAssertThrowsError(try TrackReconstructor.reconstruct(signals:signals,speeds:[1,1,1,1],verticalDrop:0.6,heightConstraint:.endpointDrop))
    }

    func testDifferentSimulatedShapesUseOneHeightAndAllowRaisedFinish() throws {
        var ends: [Vector3] = []
        for profile in SimulationProfile.allCases {
            let fixture = SimulatedTrack.generate(includeJump:false,profile:profile)
            let result = try AnalysisPipeline.analyze(.init(source:.simulation,metadata:.init(verticalDrop:0.42),calibration:fixture.calibration,samples:fixture.samples))
            XCTAssertEqual(result.groundZ,0,accuracy:1e-9)
            XCTAssertEqual(result.metrics.reconstructedHeightRange,0.42,accuracy:1e-9)
            XCTAssertNil(RunMetadata().knownTrackLength)
            if profile == .raisedFinish { XCTAssertGreaterThan(result.points.last!.position.z,0.08) }
            ends.append(result.points.last!.position)
        }
        XCTAssertGreaterThan((ends[0]-ends[1]).length,0.5)
        XCTAssertGreaterThan((ends[0]-ends[2]).length,0.2)
    }

    func testChangingOnlyHRescalesGeometrySpeedAndRuler() throws {
        let fixture = SimulatedTrack.generate(profile:.raisedFinish)
        var run = RunSession(source:.simulation,metadata:.init(verticalDrop:0.42),calibration:fixture.calibration,samples:fixture.samples)
        let a = try AnalysisPipeline.analyze(run)
        run.metadata.verticalDrop = try XCTUnwrap(run.metadata.verticalDrop)*2
        let b = try AnalysisPipeline.analyze(run)
        for (p,q) in zip(a.points,b.points) {
            XCTAssertEqual((p.position*2-q.position).length,0,accuracy:1e-8)
            XCTAssertEqual(p.speed*2,q.speed,accuracy:1e-8)
        }
        func measurement(_ r: AnalysisResult) -> TrackMeasurement {
            .init(a:TrackSampling.point(at:1.3,in:r.points)!,b:TrackSampling.point(at:5.1,in:r.points)!)
        }
        XCTAssertEqual(measurement(a).straightLine*2,measurement(b).straightLine,accuracy:1e-8)
        XCTAssertEqual(measurement(a).alongTrack*2,measurement(b).alongTrack,accuracy:1e-8)
    }

    func testOriginalSavedMetadataKeepsEndpointDropUntilEdited() throws {
        let encoder = JSONEncoder()
        var object = try JSONSerialization.jsonObject(with:encoder.encode(RunMetadata(verticalDrop:0.42))) as! [String:Any]
        object.removeValue(forKey:"heightConstraint")
        let old = try JSONDecoder().decode(RunMetadata.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertEqual(old.resolvedHeightConstraint,.endpointDrop)
        XCTAssertEqual(RunMetadata().resolvedHeightConstraint,.heightRange)
        let fixture = SimulatedTrack.generate()
        let result = try AnalysisPipeline.analyze(.init(source:.simulation,metadata:old,calibration:fixture.calibration,samples:fixture.samples))
        XCTAssertEqual(result.points.first!.position,.zero)
        XCTAssertEqual(result.points.last!.position.z,-0.42,accuracy:1e-9)
        XCTAssertEqual(result.heightConstraint,.endpointDrop)
    }

    func testRulerInterpolatesAndSeparatesChordArcHorizontalAndHeight() throws {
        let points = path([.init(0,0,0),.init(3,0,4),.init(3,4,4)])
        let a = try XCTUnwrap(TrackSampling.point(at:0.5,in:points))
        let b = try XCTUnwrap(TrackSampling.nearest(to:.init(3,2.5,4),in:points))
        XCTAssertEqual(a.position,.init(1.5,0,2))
        XCTAssertEqual(b.position,.init(3,2.5,4))
        let m = TrackMeasurement(a:a,b:b), reverse = TrackMeasurement(a:b,b:a)
        XCTAssertEqual(m.straightLine,sqrt(12.5),accuracy:1e-9)
        XCTAssertEqual(m.alongTrack,5,accuracy:1e-9)
        XCTAssertEqual(m.horizontal,sqrt(8.5),accuracy:1e-9)
        XCTAssertEqual(m.heightChange,2)
        XCTAssertEqual(reverse.straightLine,m.straightLine)
        XCTAssertEqual(reverse.alongTrack,m.alongTrack)
        XCTAssertEqual(reverse.heightChange,-m.heightChange)
    }

    func testRulerDisambiguatesCrossingsAndStationarySamplesUsingTime() throws {
        let crossed = path([.init(-1,-1,0),.init(1,1,0),.init(-1,1,0),.init(1,-1,0)])
        XCTAssertEqual(try XCTUnwrap(TrackSampling.nearest(to:.zero,in:crossed,preferredTime:0.4)).time,0.5,accuracy:1e-9)
        XCTAssertEqual(try XCTUnwrap(TrackSampling.nearest(to:.zero,in:crossed,preferredTime:2.6)).time,2.5,accuracy:1e-9)
        let still = path([.zero,.zero,.zero])
        XCTAssertEqual(TrackSampling.nearest(to:.zero,in:still,preferredTime:1.4)?.time,1.4)
        XCTAssertNil(TrackSampling.point(at:.nan,in:still))
        XCTAssertNil(TrackSampling.nearest(to:.zero,in:[]))
    }

    func testRibbonStaysFiniteOnVerticalsLoopsAndRepeatedPoints() {
        var positions = (0...100).map { i -> Vector3 in
            let t = Double(i)/100 * 2 * .pi
            return .init(sin(t),0,1-cos(t))
        }
        positions.insert(positions[0],at:0)
        let frames = TrackRibbon.frames(points:path(positions))
        XCTAssertEqual(frames.count,101)
        for frame in frames {
            XCTAssertEqual(frame.tangent.dot(frame.up),0,accuracy:1e-8)
            XCTAssertEqual(frame.lateral.length,1,accuracy:1e-8)
            XCTAssertEqual(frame.up.length,1,accuracy:1e-8)
        }
        for rails in [false,true] {
            let mesh = TrackRibbon.make(frames:frames,rails:rails)
            XCTAssertTrue(mesh.vertices.allSatisfy(\.isFinite))
            XCTAssertTrue(mesh.normals.allSatisfy { $0.isFinite && abs($0.length-1)<1e-7 })
            XCTAssertEqual(mesh.vertices.count,mesh.normals.count)
            XCTAssertEqual(mesh.vertices.count,mesh.speeds.count)
            XCTAssertTrue(mesh.triangles.allSatisfy { Int($0)<mesh.vertices.count })
            XCTAssertFalse(mesh.triangles.isEmpty)
        }
        XCTAssertTrue(TrackRibbon.frames(points:path([.zero,.zero])).isEmpty)
    }

    private func path(_ positions: [Vector3]) -> [TrackPoint] {
        var distance = 0.0
        return positions.enumerated().map { i,p in
            if i>0 { distance += (p-positions[i-1]).length }
            return .init(time:Double(i),position:p,speed:1,distance:distance)
        }
    }
}
