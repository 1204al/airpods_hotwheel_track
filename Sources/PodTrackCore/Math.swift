import Foundation

public let standardGravity = 9.80665
public func clamp(_ x: Double, _ low: Double, _ high: Double) -> Double { min(high, max(low, x)) }
public func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

public struct Vector3: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(_ x: Double = 0, _ y: Double = 0, _ z: Double = 0) { self.x = x; self.y = y; self.z = z }
    public static let zero = Vector3()
    public static let unitX = Vector3(1, 0, 0)
    public static let unitY = Vector3(0, 1, 0)
    public static let unitZ = Vector3(0, 0, 1)
    public var length: Double { sqrt(dot(self)) }
    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    public var normalized: Vector3 { length > 1e-10 ? self / length : .zero }
    public func dot(_ b: Vector3) -> Double { x*b.x + y*b.y + z*b.z }
    public func cross(_ b: Vector3) -> Vector3 { Vector3(y*b.z-z*b.y, z*b.x-x*b.z, x*b.y-y*b.x) }
    public static prefix func - (a: Vector3) -> Vector3 { a * -1 }
    public static func + (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x+b.x, a.y+b.y, a.z+b.z) }
    public static func - (a: Vector3, b: Vector3) -> Vector3 { a + -b }
    public static func * (a: Vector3, s: Double) -> Vector3 { Vector3(a.x*s, a.y*s, a.z*s) }
    public static func / (a: Vector3, s: Double) -> Vector3 { a * (1/s) }
}

public struct Quaternion: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var w: Double
    public init(x: Double = 0, y: Double = 0, z: Double = 0, w: Double = 1) {
        self.x = x; self.y = y; self.z = z; self.w = w
    }
    public init(axis: Vector3, angle: Double) {
        let v = axis.normalized * sin(angle/2)
        self.init(x: v.x, y: v.y, z: v.z, w: cos(angle/2))
    }
    public var norm: Double { sqrt(x*x + y*y + z*z + w*w) }
    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite && w.isFinite && norm > 1e-10 }
    public var normalized: Quaternion { let n = norm; return n > 1e-10 ? .init(x:x/n, y:y/n, z:z/n, w:w/n) : .init() }
    public var inverse: Quaternion { let q = normalized; return .init(x:-q.x, y:-q.y, z:-q.z, w:q.w) }
    public static func * (a: Quaternion, b: Quaternion) -> Quaternion {
        .init(x:a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,
              y:a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,
              z:a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w,
              w:a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z)
    }
    public func rotate(_ v: Vector3) -> Vector3 {
        let q = normalized, u = Vector3(q.x, q.y, q.z)
        return v + u.cross(v) * (2*q.w) + u.cross(u.cross(v)) * 2
    }
}
