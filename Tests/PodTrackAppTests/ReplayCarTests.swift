import XCTest
import SceneKit
import simd
import PodTrackCore
@testable import PodTrack

@MainActor final class ReplayCarTests: XCTestCase {
    func testCarStaysAlignedThroughVerticalAndInvertedLoopSections() {
        let radius = 0.24
        let points = (0...240).map { index -> TrackPoint in
            let angle = Double(index)/240 * 2 * Double.pi
            return .init(time:angle,position:.init(radius*sin(angle),0,radius*(1-cos(angle))),speed:radius,distance:radius*angle)
        }
        let car = ReplayCarNode(frames:TrackRibbon.frames(points:points),roadScale:1)
        XCTAssertNotNil(car.childNode(withName:"mounted-airpod",recursively:false))
        XCTAssertEqual(car.wheels.count,4)
        for angle in [0.15,Double.pi/2,Double.pi,Double.pi*1.5,Double.pi*1.94] {
            let point = TrackSampling.point(at:angle,in:points)!
            car.update(point:point)
            let forward = car.simdOrientation.act(SIMD3<Float>(1,0,0))
            let up = car.simdOrientation.act(SIMD3<Float>(0,1,0))
            // Analytic circle directions, independent of the road's transported frames.
            XCTAssertGreaterThan(simd_dot(forward,SIMD3(Float(cos(angle)),Float(sin(angle)),0)),0.999)
            XCTAssertGreaterThan(simd_dot(up,SIMD3(Float(-sin(angle)),Float(cos(angle)),0)),0.999)
            let offset = car.simdPosition-SIMD3(Float(point.position.x),Float(point.position.z),Float(-point.position.y))
            XCTAssertGreaterThan(simd_dot(offset,up),0)
            XCTAssertLessThan(simd_length(offset),0.001)
        }
    }

    func testWheelRotationStopsAtCursorAndRewindsWithoutDrift() {
        let points = [TrackPoint(time:0,position:.zero,speed:0.1,distance:0),
                      TrackPoint(time:1,position:.init(0.1,0,0),speed:0.1,distance:0.1)]
        let car = ReplayCarNode(frames:TrackRibbon.frames(points:points),roadScale:1)
        let quarterTurn = Double.pi*ReplayCarNode.wheelRadius/2
        let point = TrackPoint(time:0.5,position:.init(quarterTurn,0,0),speed:0.1,distance:quarterTurn)
        car.update(point:point)
        let spoke = car.wheels[0].simdOrientation.act(SIMD3<Float>(1,0,0))
        XCTAssertEqual(spoke.x,0,accuracy:1e-5)
        XCTAssertEqual(spoke.y,-1,accuracy:1e-5)
        let pausedPosition = car.simdPosition, pausedWheel = car.wheels[0].simdOrientation
        for _ in 0..<12 { car.update(point:point) }
        XCTAssertEqual(car.simdPosition,pausedPosition)
        XCTAssertGreaterThan(abs(simd_dot(car.wheels[0].simdOrientation.vector,pausedWheel.vector)),0.99999)
        car.update(point:points[0])
        XCTAssertGreaterThan(simd_dot(car.wheels[0].simdOrientation.act(SIMD3<Float>(1,0,0)),SIMD3<Float>(1,0,0)),0.99999)

        let relative = ReplayCarNode(frames:TrackRibbon.frames(points:points),roadScale:0.25)
        relative.update(point:.init(time:0.5,position:.init(quarterTurn*0.25,0,0),speed:0.025,distance:quarterTurn*0.25))
        XCTAssertEqual(relative.simdScale,SIMD3<Float>(repeating:0.25))
        XCTAssertEqual(relative.wheels[0].simdOrientation.act(SIMD3<Float>(1,0,0)).y,-1,accuracy:1e-5)
    }
}
