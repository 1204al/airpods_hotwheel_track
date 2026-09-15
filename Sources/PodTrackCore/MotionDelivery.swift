import Foundation

/// Host receipt time is captured on the sensor callback queue, before UI work.
/// Raw MotionSample values and their source timestamps are never rewritten.
public struct MotionDelivery: Sendable {
    public let sample: MotionSample
    public let receivedAt: TimeInterval

    public init(sample: MotionSample, receivedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.sample = sample
        self.receivedAt = receivedAt
    }
}

/// Compares elapsed source time with elapsed host time. No shared clock epoch
/// between the AirPod and Mac is assumed. Constant transport/fusion latency is
/// unobservable here; extra lag is relative to the best delivery in this stream.
public struct MotionDeliveryMonitor {
    public private(set) var extraLag: TimeInterval = 0
    public private(set) var lastReceipt: TimeInterval?
    public private(set) var lastTimestamp: TimeInterval?
    public private(set) var rejectedTimestamps = 0
    private var minimumOffset: TimeInterval?
    private var arrivals: [TimeInterval] = []

    public init() {}

    @discardableResult public mutating func append(_ delivery: MotionDelivery) -> Bool {
        guard delivery.sample.isValid, delivery.receivedAt.isFinite else { return false }
        if let lastTimestamp, delivery.sample.timestamp <= lastTimestamp {
            rejectedTimestamps += 1
            return false
        }
        if let lastReceipt, delivery.receivedAt < lastReceipt { return false }
        let offset = delivery.receivedAt - delivery.sample.timestamp
        minimumOffset = min(minimumOffset ?? offset, offset)
        extraLag = max(0, offset - (minimumOffset ?? offset))
        lastReceipt = delivery.receivedAt
        lastTimestamp = delivery.sample.timestamp
        arrivals.append(delivery.receivedAt)
        arrivals.removeAll { $0 < delivery.receivedAt - 2 }
        if arrivals.count > 200 { arrivals.removeFirst(arrivals.count - 200) }
        return true
    }

    public var arrivalRateHz: Double? {
        guard let first = arrivals.first, let last = arrivals.last, last-first >= 0.5 else { return nil }
        return Double(arrivals.count-1)/(last-first)
    }

    public var largestArrivalGap: TimeInterval? {
        zip(arrivals,arrivals.dropFirst()).map { $1-$0 }.max()
    }
}
