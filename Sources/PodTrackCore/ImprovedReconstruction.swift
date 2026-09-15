import Foundation

public struct MotionQualityInterval: Codable, Hashable, Sendable {
    public var startTime: Double
    public var endTime: Double
    public var rotationRadians: Double
    public var duration: Double { endTime-startTime }
}

public struct RepeatCircuit: Codable, Hashable, Sendable, Identifiable {
    public var startTime: Double
    public var endTime: Double
    public var directionMismatchDegrees: Double
    public var estimatedLength: Double = 0
    public var closureDistance: Double = 0
    public var id: Double { startTime }
    public var duration: Double { endTime-startTime }
}

public struct ReconstructionDiagnostics: Codable, Sendable {
    public var motionStart: Double
    public var motionEnd: Double
    public var startRestSupported: Bool
    public var endRestSupported: Bool
    public var collapsedMotion: [MotionQualityInterval]
    public var repeatCircuits: [RepeatCircuit]
    public var repeatConstraintsApplied: Bool
    public var speedFitConverged: Bool
    public var speedFitIterations: Int
    public var normalAccelerationRMS: Double
    public var accelerationResidualRMS: Double
}

/// A second, explicitly experimental method. The original AnalysisPipeline remains the baseline.
public enum ImprovedReconstruction {
    public static let version = "0.5.0-constrained-experimental"

    public static func analyze(_ run: RunSession, useRepeatedCircuits: Bool = true) throws -> AnalysisResult {
        try run.metadata.validate()
        guard let calibration = run.calibration, calibration.source == run.source else {
            throw PodTrackError.invalid("A matching mounting calibration is required for improved reconstruction.")
        }
        let processed = try process(run.samples, calibration:calibration, settings:run.metadata.settings)
        let signals = processed.samples
        let interval = restInterval(run.samples, settings:run.metadata.settings)
        let activeTime = signals[interval.end].time-signals[interval.start].time
        guard activeTime > 0.25,
              run.samples[interval.start...interval.end].contains(where:{ $0.rotationRate.length>0.15 || $0.userAcceleration.length>0.035 }) else {
            throw PodTrackError.invalid("No sustained motion was detected for improved reconstruction.")
        }
        let circuits = detectRepeatedCircuits(samples:run.samples, signals:signals, calibration:calibration)
        let enabledCircuits = useRepeatedCircuits ? circuits.filter {
            $0.startTime>=signals[interval.start].time && $0.endTime<=signals[interval.end].time
        } : []
        let fit = try ConstrainedSpeedSolver.fit(samples:run.samples, signals:signals, calibration:calibration,
                                                 settings:run.metadata.settings, interval:interval, circuits:enabledCircuits)
        let estimate = try TrackReconstructor.reconstruct(signals:signals, speeds:fit.speeds, verticalDrop:run.metadata.verticalDrop,
            knownLength:run.metadata.knownTrackLength, heightConstraint:run.metadata.resolvedHeightConstraint)
        var points = estimate.points
        let segments = RunSegmenter.attachMetrics(RunSegmenter.detect(signals,startIndex:interval.start,endIndex:interval.end),points:points,signals:signals)
        for i in points.indices { points[i].segmentLabel = RunSegmenter.labels(at:points[i].time,segments:segments) }
        let collapsed = collapsedMotion(samples:run.samples, signals:signals, points:points, speedScale:estimate.heightScale)
        let measuredCircuits = circuits.map { circuit -> RepeatCircuit in
            var value = circuit
            if let a = TrackSampling.point(at:circuit.startTime,in:points), let b = TrackSampling.point(at:circuit.endTime,in:points) {
                value.estimatedLength = b.distance-a.distance
                value.closureDistance = (b.position-a.position).length
            }
            return value
        }
        var warnings = run.recordingNotes + processed.warnings + fit.warnings + estimate.warnings
        warnings.append("Experimental constrained reconstruction. Shape and speed require independent validation; fitting height and circuit returns does not prove accuracy.")
        if !collapsed.isEmpty { warnings.append("Estimated speed remains near zero during sustained rotation. Some traveled distance may still be missing.") }
        if !enabledCircuits.isEmpty {
            warnings.append("\(enabledCircuits.count) matching circuit intervals constrain this fit. These are inferred correspondences; closure residuals are fit diagnostics, not independent accuracy measurements.")
        } else if useRepeatedCircuits {
            warnings.append("No sufficiently matching repeated inversion circuits were found. No return or equal-route constraints were applied.")
        }
        if segments.contains(where:{ $0.kind == .airborne }) {
            warnings.append("Possible airtime: the car's pointing direction may differ from its travel direction in flight.")
        }
        let speedEstimate = SpeedEstimate(speeds:fit.speeds,startIndex:interval.start,endIndex:interval.end,
            accelerationSign:fit.sign,endpointCorrection:fit.correction,warnings:[])
        var result = AnalysisResult(runID:run.id,source:run.source,recordedOrigin:run.recordedOrigin,signals:signals,points:points,
            segments:segments,metrics:MetricsCalculator.calculate(run:run,signals:signals,points:points,segments:segments,speed:speedEstimate),
            warnings:warnings,attitudeMapping:processed.attitudeMapping,inferredAccelerationSign:fit.sign,
            endpointAccelerationCorrection:fit.correction,heightScale:estimate.heightScale,horizontalScale:estimate.horizontalScale,
            unscaledDrop:estimate.unscaledDrop,unscaledHeightRange:estimate.unscaledHeightRange,heightConstraint:run.metadata.resolvedHeightConstraint,
            scaleBasis:run.metadata.scaleBasis)
        result.algorithmVersion = version
        result.reconstructionDiagnostics = .init(motionStart:signals[interval.start].time,motionEnd:signals[interval.end].time,
            startRestSupported:interval.startSupported,endRestSupported:interval.endSupported,collapsedMotion:collapsed,
            repeatCircuits:measuredCircuits,repeatConstraintsApplied:!enabledCircuits.isEmpty,speedFitConverged:fit.converged,
            speedFitIterations:fit.iterations,normalAccelerationRMS:fit.normalRMS,accelerationResidualRMS:fit.accelerationRMS)
        return result
    }

    public static func process(_ samples: [MotionSample], calibration: MountCalibration, settings: ReconstructionSettings) throws -> ProcessedSignals {
        var rawSettings = settings; rawSettings.smoothingSeconds = 0
        // Reuse frame validation and mapping selection. Do not bypass sensor/reference reset checks.
        let raw = try SignalProcessor.process(samples,calibration:calibration,settings:rawSettings)
        let times = raw.samples.map(\.time), directions = raw.samples.map(\.direction)
        let x = SignalProcessor.smooth(directions.map(\.x),times:times,window:settings.smoothingSeconds)
        let y = SignalProcessor.smooth(directions.map(\.y),times:times,window:settings.smoothingSeconds)
        let z = SignalProcessor.smooth(directions.map(\.z),times:times,window:settings.smoothingSeconds)
        let tangent = SignalProcessor.smooth(raw.samples.map(\.tangentialUserAcceleration),times:times,window:settings.smoothingSeconds)
        let vertical = SignalProcessor.smooth(raw.samples.map(\.verticalUserAcceleration),times:times,window:settings.smoothingSeconds)
        var result = raw.samples
        var ambiguous = false
        for i in result.indices {
            let vector = Vector3(x[i],y[i],z[i])
            if vector.length < 0.2 { ambiguous = true }
            // A near-cancelled mean does not define a tangent. Retain the measured sample and warn.
            result[i].forwardDirection = vector.length >= 0.2 ? vector.normalized : directions[i]
            result[i].slope = asin(clamp(result[i].direction.z,-1,1))
            result[i].heading = atan2(result[i].direction.y,result[i].direction.x)
            result[i].tangentialUserAcceleration = tangent[i]
            result[i].verticalUserAcceleration = vertical[i]
            // Gyro rotation about gravity is defined through a vertical passage. Planar heading
            // derivatives are ill-conditioned there and must not drive the geometry or warnings.
            result[i].turnRate = samples[i].rotationRate.dot(-samples[i].gravity.normalized)
        }
        let headings = SignalProcessor.unwrap(result.map(\.heading))
        let turning = SignalProcessor.smooth(result.map(\.turnRate),times:times,window:settings.smoothingSeconds)
        for i in result.indices { result[i].heading = headings[i]; result[i].turnRate = turning[i] }
        var warnings = raw.warnings.filter { !$0.hasPrefix("Abrupt heading changes detected.") }
        if ambiguous { warnings.append("Some orientation windows span opposing directions. Their measured tangents were retained; use a shorter orientation smoothing window.") }
        return .init(samples:result,attitudeMapping:raw.attitudeMapping,warnings:warnings)
    }

    public static func collapsedMotion(samples: [MotionSample], signals: [ProcessedSample], points: [TrackPoint], speedScale: Double = 1) -> [MotionQualityInterval] {
        guard samples.count == signals.count, points.count == samples.count, samples.count>1 else { return [] }
        var result: [MotionQualityInterval] = [], first: Int?
        func append(_ end: Int) {
            guard let start = first, end>start else { return }
            let duration = signals[end].time-signals[start].time
            guard duration>=0.20 else { return }
            let rotation = (start+1...end).reduce(0.0) { sum,i in
                sum + (samples[i-1].rotationRate.length+samples[i].rotationRate.length)*0.5*(signals[i].time-signals[i-1].time)
            }
            if rotation>0.35 { result.append(.init(startTime:signals[start].time,endTime:signals[end].time,rotationRadians:rotation)) }
        }
        for i in signals.indices {
            if points[i].speed/max(speedScale,1e-10) < 0.015 {
                if first == nil { first = i }
            } else { if first != nil { append(i-1) }; first = nil }
        }
        if first != nil { append(signals.count-1) }
        return result
    }

    struct MotionInterval {
        var start: Int; var end: Int
        var startSupported: Bool; var endSupported: Bool
    }

    static func restInterval(_ samples: [MotionSample], settings: ReconstructionSettings) -> MotionInterval {
        guard settings.startsAndEndsAtRest, samples.count>15 else {
            return .init(start:0,end:samples.count-1,startSupported:false,endSupported:false)
        }
        // Only inspect contiguous windows at the recording edges. Constant-velocity interior
        // sections can look quiet, so they must never create additional rest constraints.
        func stable(_ range: ClosedRange<Int>) -> Bool {
            let window = Array(samples[range])
            guard let first = window.first, let last = window.last, last.timestamp-first.timestamp>=0.28 else { return false }
            let omega = median(window.map { $0.rotationRate.length })
            let a = vectorMedian(window.map(\.userAcceleration)), g = vectorMedian(window.map(\.gravity))
            let aSpread = sqrt(window.map { pow(($0.userAcceleration-a).length,2) }.reduce(0,+)/Double(window.count))
            let gSpread = sqrt(window.map { pow(($0.gravity-g).length,2) }.reduce(0,+)/Double(window.count))
            return omega<0.12 && window.filter { $0.rotationRate.length>0.3 }.count<=window.count/10 && aSpread<0.045 && gSpread<0.012
        }
        let times = samples.map(\.timestamp), n = samples.count
        var start = 0, end = n-1, startOK = false, endOK = false
        var j = 0
        for i in 0..<n {
            while j<n-1 && times[j]-times[i]<0.30 { j += 1 }
            guard stable(i...j) else { break }
            startOK = true; start = i
        }
        var i = n-1
        for j in stride(from:n-1,through:0,by:-1) {
            while i>0 && times[j]-times[i]<0.30 { i -= 1 }
            guard stable(i...j) else { break }
            endOK = true; end = j
        }
        return .init(start:start,end:max(start,end),startSupported:startOK,endSupported:endOK)
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted(), middle = sorted.count/2
        return sorted.count%2 == 0 ? (sorted[middle-1]+sorted[middle])/2 : sorted[middle]
    }
    static func vectorMedian(_ values: [Vector3]) -> Vector3 { .init(median(values.map(\.x)),median(values.map(\.y)),median(values.map(\.z))) }

    /// Match entire direction sequences by accumulated turning angle, making comparison
    /// independent of lap speed. An inversion by itself is never accepted as a repeated route.
    public static func detectRepeatedCircuits(samples: [MotionSample], signals: [ProcessedSample], calibration: MountCalibration) -> [RepeatCircuit] {
        guard samples.count == signals.count, samples.count>10 else { return [] }
        var landmarks: [Int] = [], start: Int?
        let up = samples.map { calibration.upDevice.dot(-$0.gravity.normalized) }
        for i in samples.indices {
            if up[i]<0 {
                if start == nil { start = i }
            } else if let first = start {
                let last = i-1
                if samples[last].timestamp-samples[first].timestamp>=0.06,
                   let apex = (first...last).min(by:{up[$0]<up[$1]}), up[apex] < -0.75,
                   samples[first...last].map({$0.rotationRate.length}).max() ?? 0 > 0.5 {
                    landmarks.append(apex)
                }
                start = nil
            }
        }
        struct Candidate { var start: Int; var end: Int; var arc: Double; var signature: [Vector3] }
        var candidates: [Candidate] = []
        for (a,b) in zip(landmarks,landmarks.dropFirst()) {
            let duration = signals[b].time-signals[a].time
            guard duration>=0.5, duration<=30 else { continue }
            let phase = angularProgress(signals:signals,start:a,end:b)
            guard let arc = phase.last, arc>4 else { continue }
            var signature: [Vector3] = [], j = a
            for k in 0...40 {
                let target = arc*Double(k)/40
                while j<b-1 && phase[j-a+1]<target { j += 1 }
                let u = clamp((target-phase[j-a])/max(1e-10,phase[j-a+1]-phase[j-a]),0,1)
                signature.append((signals[j].direction*(1-u)+signals[j+1].direction*u).normalized)
            }
            candidates.append(.init(start:a,end:b,arc:arc,signature:signature))
        }
        guard candidates.count>=2 else { return [] }
        // Select the largest mutually compatible group. Do not mix separately repeated routes.
        func mismatch(_ a: Candidate, _ b: Candidate) -> Double {
            guard min(a.arc,b.arc)/max(a.arc,b.arc)>0.80 else { return .infinity }
            return sqrt(zip(a.signature,b.signature).map { pow(degrees(acos(clamp($0.dot($1),-1,1))),2) }.reduce(0,+)/Double(a.signature.count))
        }
        var best: [Int] = []
        for i in candidates.indices {
            var group = [i]
            for j in candidates.indices where j != i {
                if group.allSatisfy({mismatch(candidates[$0],candidates[j])<15}) { group.append(j) }
            }
            if group.count>best.count { best = group }
        }
        guard best.count>=2, let reference = best.first else { return [] }
        return best.sorted().map { i in
            .init(startTime:signals[candidates[i].start].time,endTime:signals[candidates[i].end].time,
                  directionMismatchDegrees:mismatch(candidates[reference],candidates[i]))
        }
    }

    static func angularProgress(signals: [ProcessedSample], start: Int, end: Int) -> [Double] {
        var arc = [0.0]
        for i in start+1...end { arc.append(arc.last!+acos(clamp(signals[i-1].direction.dot(signals[i].direction),-1,1))) }
        return arc
    }
}

private enum ConstrainedSpeedSolver {
    struct Fit {
        var speeds: [Double]; var sign: Double; var correction: Double; var warnings: [String]
        var converged: Bool; var iterations: Int; var normalRMS: Double; var accelerationRMS: Double
    }
    struct Row {
        var indices: [Int]; var coefficients: [Double]; var target: Double; var weight: Double
        func value(_ x: [Double]) -> Double { zip(indices,coefficients).reduce(0) { $0+x[$1.0]*$1.1 } }
    }

    static func fit(samples: [MotionSample], signals: [ProcessedSample], calibration: MountCalibration,
                    settings: ReconstructionSettings, interval: ImprovedReconstruction.MotionInterval, circuits: [RepeatCircuit]) throws -> Fit {
        let n = signals.count, times = signals.map(\.time), start = interval.start, end = interval.end
        var warnings: [String] = []
        if settings.startsAndEndsAtRest && (!interval.startSupported || !interval.endSupported) {
            warnings.append("A stable recording edge is missing. Only supported rest edges are constrained; straight constant-speed travel is indistinguishable from rest using an IMU alone.")
        }
        let measuredStartBias = interval.startSupported ? ImprovedReconstruction.median(Array(signals[0...start].map(\.tangentialUserAcceleration))) : nil
        let measuredEndBias = interval.endSupported ? ImprovedReconstruction.median(Array(signals[end..<n].map(\.tangentialUserAcceleration))) : nil
        // A single supported edge still measures the constant tangential bias. Interpolate
        // drift only when both edges support independent measurements.
        let startBias = measuredStartBias ?? measuredEndBias ?? 0
        let endBias = measuredEndBias ?? startBias
        let turnVectors = samples.map { $0.rotationRate.cross(calibration.forwardDevice) }
        let rawNormal = samples.indices.compactMap { i -> Double? in
            let w = turnVectors[i], a = samples[i].userAcceleration*standardGravity
            guard w.length>1.5, a.length>0.3 else { return nil }
            return a.dot(w)/w.dot(w)
        }
        let sign: Double
        switch settings.accelerationPolarity {
        case .asReported: sign = 1
        case .inverted: sign = -1
        case .automatic:
            let negativeFraction = rawNormal.isEmpty ? 0.5 : Double(rawNormal.filter{$0<0}.count)/Double(rawNormal.count)
            if rawNormal.count>=20 && (negativeFraction>0.70 || negativeFraction<0.30) {
                sign = negativeFraction>0.70 ? -1 : 1
                warnings.append("Acceleration polarity inferred from centripetal motion under the rigid-mount/travel-direction assumption. Validate it with a known ramp.")
            } else {
                let evidence = signals[start...end].filter { $0.time-times[start]<1.2 && $0.slope < -0.08 }
                let score = evidence.map { ($0.tangentialUserAcceleration-startBias) * -sin($0.slope) }.reduce(0,+)
                sign = score<0 ? -1 : 1
                warnings.append("Acceleration polarity inferred from early descent; turning evidence was insufficient. Validate the sign with a known ramp.")
            }
        }
        let acceleration = signals.map { s -> Double in
            let u = clamp((s.time-times[start])/max(0.001,times[end]-times[start]),0,1)
            let bias = interval.startSupported && interval.endSupported ? startBias+(endBias-startBias)*u : startBias
            let sensor = sign*(s.tangentialUserAcceleration-bias)
            let slopeModel = -standardGravity*sin(s.slope)-settings.rollingResistance
            let weight = s.supportProxyG<0.25 ? 0 : settings.gravityModelWeight*exp(-abs(sensor-slopeModel)/2)
            return (1-weight)*sensor+weight*slopeModel
        }
        var rows: [Row] = []
        for i in start+1...end {
            let dt = times[i]-times[i-1]
            rows.append(.init(indices:[i-1,i],coefficients:[-1,1],target:(acceleration[i-1]+acceleration[i])*dt/2,weight:1/(16*dt)))
        }
        if end>start+1 {
            for i in start+1..<end {
                let left = times[i]-times[i-1], right = times[i+1]-times[i], dt = (left+right)/2
                rows.append(.init(indices:[i-1,i,i+1],coefficients:[1/left,-1/left-1/right,1/right],target:0,weight:1/(40_000*dt)))
            }
        }
        var normalObservations: [(Int,Double,Double)] = []
        for i in start...end {
            let w = turnVectors[i], squared = w.dot(w)
            guard squared>1, signals[i].supportProxyG>=0.25 else { continue }
            let a = samples[i].userAcceleration*(sign*standardGravity)
            let normal = a-calibration.forwardDevice*a.dot(calibration.forwardDevice)
            let observedSpeed = normal.dot(w)/squared
            let mismatch = (normal-w*observedSpeed).length
            let dt = i>start ? times[i]-times[i-1] : times[min(i+1,end)]-times[i]
            let weight = dt*min(squared,400)/25 / max(1,mismatch/6)
            rows.append(.init(indices:[i],coefficients:[1],target:observedSpeed,weight:weight))
            normalObservations.append((i,observedSpeed,squared))
        }
        if normalObservations.isEmpty { warnings.append("No usable turning-based speed observations. Absolute initial speed remains unobserved without a rest endpoint or another measurement.") }
        else { warnings.append("Turning acceleration helps constrain speed. This assumes the AirPod is rigidly mounted, the car points along its travel, and sensor offset from the car's center is small.") }

        func rowFrom(_ coefficients: [Double], weight: Double) -> Row {
            let indices = coefficients.indices.filter { abs(coefficients[$0])>1e-12 }
            return .init(indices:indices,coefficients:indices.map {coefficients[$0]},target:0,weight:weight)
        }
        var routeRows: [[Double]] = [], blocks: [[[Double]]] = []
        for circuit in circuits {
            guard let a = times.firstIndex(where:{abs($0-circuit.startTime)<1e-6}),
                  let b = times.firstIndex(where:{abs($0-circuit.endTime)<1e-6}), a>=start, b<=end else { continue }
            var length = Array(repeating:0.0,count:n)
            for i in a..<b {
                let dt = times[i+1]-times[i]
                length[i] += dt/2; length[i+1] += dt/2
            }
            routeRows.append(length)
            for axis in 0..<3 {
                let coefficients = signals.indices.map { i -> Double in
                    let d = signals[i].direction
                    return length[i]*(axis == 0 ? d.x : axis == 1 ? d.y : d.z)
                }
                rows.append(rowFrom(coefficients,weight:1/(0.06*0.06)))
            }
            let arc = ImprovedReconstruction.angularProgress(signals:signals,start:a,end:b), total = arc.last!
            var sections = Array(repeating:Array(repeating:0.0,count:n),count:8)
            for bin in 0..<8 {
                for i in a..<b {
                    let low = arc[i-a]/total, high = arc[i-a+1]/total
                    let overlap = max(0,min(high,Double(bin+1)/8)-max(low,Double(bin)/8))
                    let fraction = overlap/max(1e-10,high-low), dt = times[i+1]-times[i]
                    sections[bin][i] += fraction*dt/2; sections[bin][i+1] += fraction*dt/2
                }
            }
            blocks.append(sections)
        }
        if let reference = routeRows.first {
            for route in routeRows.dropFirst() { rows.append(rowFrom(zip(route,reference).map(-),weight:100)) }
        }
        if let reference = blocks.first {
            for lap in blocks.dropFirst() {
                for bin in 0..<8 { rows.append(rowFrom(zip(lap[bin],reference[bin]).map(-),weight:100)) }
            }
        }
        // A small magnitude regularizer selects a finite minimum when speed is unobservable.
        // It does not provide a positive floor or fabricate travel in a stationary recording.
        let regularization = times.indices.map { i in
            0.05*(times[min(n-1,i+1)]-times[max(0,i-1)])/2
        }
        var rhs = Array(repeating:0.0,count:n), bound = regularization
        for row in rows {
            let sum = row.coefficients.map(abs).reduce(0,+)
            for (i,c) in zip(row.indices,row.coefficients) {
                rhs[i] += row.weight*c*row.target
                bound[i] += row.weight*abs(c)*sum
            }
        }
        let lipschitz = max(bound.max() ?? 1,0.001)
        func multiply(_ x: [Double]) -> [Double] {
            var result = x.indices.map { x[$0]*regularization[$0] }
            for row in rows {
                let value = row.weight*row.value(x)
                for (i,c) in zip(row.indices,row.coefficients) { result[i] += c*value }
            }
            return result
        }
        // Projected accelerated gradient on a convex quadratic, with nonnegative speed in
        // the optimization itself. Sparse rows avoid an O(n²) matrix for long recordings.
        var x = Array(repeating:0.0,count:n), y = x, momentum = 1.0
        var converged = false, iterations = 0
        for iteration in 0..<12000 {
            if iteration%25 == 0 { try Task.checkCancellation() }
            let gradient = zip(multiply(y),rhs).map(-)
            var next = y.indices.map { max(0,y[$0]-gradient[$0]/lipschitz) }
            for i in 0..<start { next[i] = 0 }
            if interval.startSupported { next[start] = 0 }
            if interval.endSupported { next[end] = 0 }
            if end<n-1 { for i in end+1..<n { next[i] = 0 } }
            let newMomentum = (1+sqrt(1+4*momentum*momentum))/2
            let delta = zip(next,x).map(-)
            let restart = next.indices.reduce(0.0) { $0 + delta[$1]*(y[$1]-next[$1]) }>0
            y = restart ? next : next.indices.map { next[$0]+(momentum-1)/newMomentum*delta[$0] }
            x = next; momentum = restart ? 1 : newMomentum; iterations = iteration+1
            if iteration%50 == 49 {
                let g = zip(multiply(x),rhs).map(-)
                let residual = (start...end).filter { !($0 == start && interval.startSupported) && !($0 == end && interval.endSupported) }
                    .map { x[$0]>1e-8 ? abs(g[$0]) : max(0,-g[$0]) }.max() ?? 0
                if residual < 1e-4 { converged = true; break }
            }
        }
        guard x.allSatisfy(\.isFinite), (x.max() ?? 0)>0.03 else { throw PodTrackError.invalid("The constrained fit could not recover usable forward speed. Check polarity, mounting and motion evidence.") }
        if !converged { warnings.append("The speed solver reached its iteration limit. Compare residuals before using this estimate.") }
        var impulse = 0.0, accelerationError = 0.0
        for i in start+1...end {
            let dt = times[i]-times[i-1], a = (acceleration[i]+acceleration[i-1])/2
            impulse += a*dt; accelerationError += pow((x[i]-x[i-1])/dt-a,2)*dt
        }
        let normalError = normalObservations.map { pow(x[$0.0]-$0.1,2)*$0.2 }.reduce(0,+)
        let normalRMS = sqrt(normalError/Double(max(1,normalObservations.count)))
        if normalRMS>6 { warnings.append("Turning acceleration and fitted speed disagree substantially. Impacts, sensor offset, filtering or mounting error may affect this estimate.") }
        return .init(speeds:x,sign:sign,correction:(impulse-(x[end]-x[start]))/max(0.001,times[end]-times[start]),warnings:warnings,
            converged:converged,iterations:iterations,normalRMS:normalRMS,
            accelerationRMS:sqrt(accelerationError/max(0.001,times[end]-times[start])))
    }
}
