import Foundation
import PodTrackCore

@MainActor final class SimulatedTrackMotionSource: MotionSource {
    let kind: SourceKind = .simulation
    private(set) var status = MotionSourceStatus(connected:false,available:true,active:false,authorization:"Not applicable (simulation)",detail:"Explicit simulation source. No hardware connection is implied.")
    var onSamples: (([MotionDelivery]) -> Void)?
    var onStatus: ((MotionSourceStatus) -> Void)?
    var onEvent: ((String) -> Void)?
    var onFinished: (() -> Void)?
    private var timer: Timer?
    private var index = 0
    private(set) var fixture = SimulatedTrack.generate()
    func configure(drop: Double, includeJump: Bool, variation: Double = 0, profile: SimulationProfile = .circuit) {
        fixture = SimulatedTrack.generate(drop:drop,includeJump:includeJump,variation:variation,profile:profile)
    }
    func start() {
        stop(); index = 0
        status.active = true; status.requested = true; status.detail = "Simulated input · 50 Hz replay · no real sensor measurements."
        onEvent?("Simulation started (explicit selection)"); onStatus?(status)
        timer = Timer.scheduledTimer(withTimeInterval:0.02,repeats:true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.index < self.fixture.samples.count else {
                    self.stop(); self.onEvent?("Simulation finished"); self.onFinished?(); return
                }
                self.onSamples?([.init(sample:self.fixture.samples[self.index])]); self.index += 1
            }
        }
    }
    func stop() { timer?.invalidate(); timer = nil; status.active = false; status.requested = false; onStatus?(status) }
    func refreshStatus() { onStatus?(status) }
}
