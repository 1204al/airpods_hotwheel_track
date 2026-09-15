import Foundation

public struct SimulationFixture: Sendable {
    public var samples: [MotionSample]
    /// Ground truth exists only for tests; it is never passed to the reconstruction pipeline.
    public var referencePositions: [Vector3]
    public var referenceSpeeds: [Double]
    public var calibration: MountCalibration
}

public enum SimulationProfile: String, CaseIterable, Sendable {
    case circuit = "Curved circuit", sBends = "S-bends", raisedFinish = "Raised finish"
}

public enum SimulatedTrack {
    public static func generate(drop: Double = 0.42, sampleRate: Double = 50, includeJump: Bool = true, variation: Double = 0,
                                profile: SimulationProfile = .circuit) -> SimulationFixture {
        let hz = clamp(sampleRate,20,200), dt = 1/hz
        let count = Int(6.8*hz)+1
        let times = (0..<count).map { Double($0)*dt }
        let mount = Quaternion(axis:Vector3(1,2,3),angle:0.83)
        let calibration = MountCalibration(forwardDevice:mount.inverse.rotate(.unitX),upDevice:mount.inverse.rotate(.unitZ),sensorLocation:.left,source:.simulation)
        func smooth(_ t: Double, _ a: Double, _ b: Double) -> Double { let u = clamp((t-a)/(b-a),0,1); return u*u*(3-2*u) }
        func slope(_ t: Double) -> Double {
            if profile == .raisedFinish {
                return -0.65*(1-smooth(t,1.3,2.3)) + 0.26*smooth(t,4.5,5.2)
            }
            return -0.58*(1-smooth(t,1.4,2.2)) + 0.19*(smooth(t,3.9,4.2)-smooth(t,4.4,4.65))
                - 0.23*(smooth(t,4.55,4.75)-smooth(t,4.9,5.05))
        }
        func heading(_ t: Double) -> Double {
            switch profile {
            case .circuit: return 1.32*smooth(t,2.4,3.4)-0.34*smooth(t,4.5,5.0)
            case .sBends: return 1.1*smooth(t,1.9,2.8)-1.8*smooth(t,3.0,4.2)+0.7*smooth(t,4.8,5.6)
            case .raisedFinish: return 0.8*smooth(t,2.0,3.1)+0.6*smooth(t,4.0,4.9)
            }
        }
        let baseVelocity = times.map { t -> Vector3 in
            let v = (1.2+variation*0.08)*smooth(t,0.6,1.8)*(1-smooth(t,5.6,6.2)) * (1-0.20*(smooth(t,3.9,4.25)-smooth(t,4.65,5.0)))
            return Vector3(cos(slope(t))*cos(heading(t)),cos(slope(t))*sin(heading(t)),sin(slope(t))) * v
        }
        var positions = [Vector3.zero]
        for i in 1..<count { positions.append(positions[i-1]+(baseVelocity[i-1]+baseVelocity[i])*(0.5*dt)) }
        let scale = max(0.001,drop) / max(0.001,positions.map(\.z).max()!-positions.map(\.z).min()!)
        positions = positions.map { $0 * scale }
        for i in 0..<count {
            let t = times[i]
            if (3.65...3.87).contains(t) {
                positions[i].z += 0.009*pow(sin(.pi*(t-3.65)/0.22),2)
            }
            if includeJump, (5.12...5.30).contains(t) {
                let tau = t-5.12
                positions[i].z += 0.5*standardGravity*tau*(0.18-tau)
            }
        }
        func derivative(_ values: [Vector3]) -> [Vector3] {
            values.indices.map { i in
                let a = max(0,i-1), b = min(count-1,i+1)
                return (values[b]-values[a])/(Double(b-a)*dt)
            }
        }
        let velocities = derivative(positions), accelerations = derivative(velocities)
        let quaternions = times.indices.map { i -> Quaternion in
            let v = velocities[i], theta = v.length > 0.02 ? asin(clamp(v.normalized.z,-1,1)) : slope(times[i])
            let bank = 0.10*(smooth(times[i],2.4,2.7)-smooth(times[i],3.1,3.4))
            return (Quaternion(axis:.unitZ,angle:heading(times[i])) * Quaternion(axis:.unitY,angle:-theta) * Quaternion(axis:.unitX,angle:bank) * mount).normalized
        }
        let samples = times.indices.map { i -> MotionSample in
            let q = quaternions[i]
            let a = max(0,i-1), b = min(count-1,i+1)
            var delta = (quaternions[a].inverse * quaternions[b]).normalized
            if delta.w < 0 { delta = .init(x:-delta.x,y:-delta.y,z:-delta.z,w:-delta.w) }
            let omega = Vector3(delta.x,delta.y,delta.z) * (2/(Double(b-a)*dt))
            // Core Motion total acceleration is gravity + userAcceleration. Simulate its
            // accelerometer convention: free fall has near-zero total, i.e. ua = -gravity.
            let noise = Vector3(sin(times[i]*31),cos(times[i]*23),sin(times[i]*37)) * 0.0015
            let ua = q.inverse.rotate(-accelerations[i]/standardGravity) + noise
            let roll = atan2(2*(q.w*q.x+q.y*q.z),1-2*(q.x*q.x+q.y*q.y))
            let pitch = asin(clamp(2*(q.w*q.y-q.z*q.x),-1,1))
            let yaw = atan2(2*(q.w*q.z+q.x*q.y),1-2*(q.y*q.y+q.z*q.z))
            return .init(timestamp:times[i],attitude:q,roll:roll,pitch:pitch,yaw:yaw,
                         rotationRate:omega,userAcceleration:ua,gravity:q.inverse.rotate(.init(0,0,-1)),sensorLocation:.left)
        }
        return .init(samples:samples,referencePositions:positions,referenceSpeeds:velocities.map(\.length),calibration:calibration)
    }
}
