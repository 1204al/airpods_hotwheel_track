import Foundation

/// Fixed-capacity ring; recording uses a separate lossless buffer.
public struct MotionBuffer: Sendable {
    private var storage: [MotionSample?]
    private var head = 0
    public private(set) var count = 0
    public let capacity: Int
    public init(capacity: Int = 1500) {
        self.capacity = max(2, capacity)
        storage = Array(repeating: nil, count: max(2, capacity))
    }
    public mutating func append(_ sample: MotionSample) {
        guard sample.isValid else { return }
        storage[head] = sample; head = (head + 1) % capacity; count = min(count + 1, capacity)
    }
    public var samples: [MotionSample] {
        (0..<count).compactMap { storage[(head - count + $0 + capacity) % capacity] }
    }
    /// A bounded backwards scan for pose validation; avoids copying the whole
    /// 30-second diagnostic buffer every time a live label is evaluated.
    public func recent(seconds: TimeInterval) -> [MotionSample] {
        guard count > 0, let newest = storage[(head-1+capacity)%capacity] else { return [] }
        var result: [MotionSample] = []
        for offset in 1...count {
            guard let sample = storage[(head-offset+capacity)%capacity], sample.timestamp >= newest.timestamp-seconds else { break }
            result.append(sample)
        }
        return result.reversed()
    }
    public mutating func clear() { self = .init(capacity: capacity) }
}

public struct SampleStatistics: Sendable {
    public var frequencyHz: Double = 0
    public var jitterMilliseconds: Double = 0
    public var largestGap: Double = 0
    public init(samples: [MotionSample]) {
        let intervals = zip(samples, samples.dropFirst()).map { $1.timestamp - $0.timestamp }.filter { $0 > 0 }
        guard !intervals.isEmpty else { return }
        let mean = intervals.reduce(0,+) / Double(intervals.count)
        frequencyHz = 1/mean
        jitterMilliseconds = sqrt(intervals.map { pow($0-mean,2) }.reduce(0,+) / Double(intervals.count)) * 1000
        largestGap = intervals.max() ?? 0
    }
}
