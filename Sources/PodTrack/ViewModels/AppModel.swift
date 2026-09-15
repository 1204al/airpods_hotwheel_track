import SwiftUI
import PodTrackCore

struct DebugEvent: Identifiable {
    let id = UUID()
    let date = Date()
    let message: String
}

@MainActor final class LiveMotionPresentation: ObservableObject {
    @Published private(set) var sample: MotionSample?
    func update(_ sample: MotionSample?) { self.sample = sample }
}

@MainActor final class AppModel: ObservableObject {
    @Published var status = MotionSourceStatus()
    var latest: MotionSample?
    var sampleCount = 0
    var sampleAge: Double?
    var history: [MotionSample] = []
    var statistics = SampleStatistics(samples: [])
    // Sensor values do not invalidate the entire application for every sample.
    // General telemetry refreshes at 10 Hz; the small live pose view at up to 30 Hz.
    let liveMotion = LiveMotionPresentation()
    private(set) var deliveryMonitor = MotionDeliveryMonitor()
    private(set) var uiDeliveryDelay: TimeInterval?
    private(set) var longestUIWait: TimeInterval = 0
    private(set) var invalidSampleCount = 0
    @Published var events: [DebugEvent] = []
    @Published var isDashboardPaused = false
    @Published var area: AppArea? = .record
    @Published private(set) var selectedBud: RecordingBud = .right
    @Published var setup = RunMetadata()
    @Published var dropCentimeters = String(format:"%.0f",RunMetadata.defaultHeightMeters*100)
    @Published var knownLengthCentimeters = ""
    var heightIsKnown: Bool {
        get { setup.verticalDrop != nil }
        set { setup.verticalDrop = newValue ? RunMetadata.defaultHeightMeters : nil }
    }
    @Published private(set) var calibration: MountCalibration?
    @Published private(set) var calibrationProfiles: [SensorLocation:MountCalibration] = [:]
    @Published private(set) var unsavedCalibrationSides: Set<SensorLocation> = []
    @Published private(set) var hasLevelPose = false
    @Published private(set) var captureStatus: String?
    private var pendingCapture: (nose: Bool, deadline: TimeInterval, afterTimestamp: TimeInterval?)?
    private var lastCaptureIssue: String?
    @Published var recording = false
    @Published var recordedCount = 0
    @Published var recordingDuration: Double = 0
    @Published var runs: [RunSession] = []
    @Published private(set) var deletedRuns: [RunSession] = []
    @Published var lastDeletedRunID: UUID?
    @Published private(set) var reconstructionMethod: ReconstructionMethod = .improved
    @Published private(set) var comparedRunIDs: Set<UUID> = []
    @Published private(set) var comparisonColors: [UUID:Int] = [:]
    @Published var comparisonNotice: String?
    @Published var selectedRunID: UUID? {
        didSet { if selectedRunID != oldValue { rulerSelection = .init(); cursorTime = 0 } }
    }
    @Published var errorMessage: String?
    @Published var unsavedIDs: Set<UUID> = []
    @Published var recordRawOnly = false
    @Published var selectedSource: SourceKind = .airPods
    @Published var simulationIncludesJump = true
    @Published var simulationProfile: SimulationProfile = .circuit
    @Published var analyses: [UUID:AnalysisResult] = [:]
    @Published var analysisErrors: [UUID:String] = [:]
    @Published var analysingIDs: Set<UUID> = []
    private var analysisCache: [ReconstructionMethod:[UUID:AnalysisResult]] = [:]
    private var errorCache: [ReconstructionMethod:[UUID:String]] = [:]
    private var analysisTasks: [UUID:(token:UUID,task:Task<Void,Never>)] = [:]
    @Published var cursorTime: Double = 0
    @Published var rulerSelection = TrackRulerSelection()
    @Published var rulerEnabled = false
    private var recorder = RunRecorder()
    private var isReceivingMotion = false
    private var levelPose: [MotionSample] = []
    let store: RunStore
    let calibrationStore: CalibrationStore
    private var source: any MotionSource
    private var buffer = MotionBuffer()
    private var receivedAt: TimeInterval?
    private var timer: Timer?
    private var didAttemptAutoConnect = false
    var sourceKind: SourceKind { source.kind }

    init(motionSource: (any MotionSource)? = nil, store: RunStore = RunStore()) {
        source = motionSource ?? AirPodsMotionSource()
        self.store = store
        // Keep injected libraries (tests and previews included) fully isolated.
        calibrationStore = CalibrationStore(directory:store.directory.appendingPathComponent("Calibrations",isDirectory:true))
        selectedSource = source.kind
        let profiles = calibrationStore.load()
        calibrationProfiles = profiles.calibrations
        restoreCalibration()
        attachSource()
        log("PodTrack ready. Source: \(source.kind.rawValue). Hardware has not been verified.")
        do {
            let loaded = try store.load()
            runs = loaded.runs; selectedRunID = runs.first?.id
            loaded.warnings.forEach { log($0) }
            if !loaded.warnings.isEmpty { errorMessage = loaded.warnings.joined(separator:"\n") }
        } catch { errorMessage = "Could not read the run library: \(error.localizedDescription)" }
        reloadDeletedRuns()
        profiles.warnings.forEach { log($0) }
        if !profiles.warnings.isEmpty { errorMessage = ([errorMessage].compactMap { $0 } + profiles.warnings).joined(separator:"\n") }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer,forMode:.common)
        self.timer = timer
    }
    func startMotion() {
        guard !recording, !status.active else { return }
        clearBuffer(); latest = nil; receivedAt = nil; sampleAge = nil; sampleCount = 0
        source.start()
    }
    func startAuthorizedMotionIfNeeded() {
        guard !didAttemptAutoConnect else { return }
        didAttemptAutoConnect = true
        if sourceKind == .airPods, status.authorization == "Authorized" { startMotion() }
    }
    func retryMotion() {
        guard !recording else { return }
        source.stop()
        latest = nil; receivedAt = nil; sampleAge = nil; sampleCount = 0
        clearBuffer(); restoreCalibration()
        source.start()
    }
    func selectBud(_ bud: RecordingBud) {
        guard !recording, selectedBud != bud else { return }
        selectedBud = bud
        clearBuffer(); restoreCalibration()
        log("Recording requires the \(bud.rawValue.lowercased()) AirPod. Core Motion still chooses the streaming sensor; other-bud samples remain diagnostic only.")
    }
    private func restoreCalibration() {
        cancelCapture()
        levelPose = []; hasLevelPose = false
        calibration = sourceKind == .airPods ? calibrationProfiles[selectedBud.location] : nil
    }
    var recordingSourceLabel: String { sourceKind == .airPods ? "\(selectedBud.rawValue) AirPod" : "Simulation" }
    var hasMatchingCalibration: Bool {
        guard let calibration else { return false }
        return calibration.source == sourceKind && (sourceKind == .simulation || calibration.sensorLocation == selectedBud.location)
    }
    func recalibrateSelectedBud() {
        guard !recording, sourceKind == .airPods else { return }
        do {
            try discardCalibration(for:selectedBud.location)
            restoreCalibration()
        } catch { errorMessage = "Could not reset the \(recordingSourceLabel) calibration: \(error.localizedDescription)" }
    }
    private func discardCalibration(for side: SensorLocation) throws {
        try calibrationStore.remove(for:side)
        calibrationProfiles[side] = nil; unsavedCalibrationSides.remove(side)
    }
    func saveCalibration(for side: SensorLocation) {
        guard let profile = calibrationProfiles[side] else { return }
        do {
            try calibrationStore.save(profile); unsavedCalibrationSides.remove(side)
            log("\(side.rawValue.capitalized) AirPod mounting calibration saved on this Mac.")
        } catch {
            unsavedCalibrationSides.insert(side)
            errorMessage = "The \(side.rawValue) AirPod calibration works for this session but could not be saved: \(error.localizedDescription). Use Retry saving calibration before closing."
        }
    }
    private func attachSource() {
        source.onSamples = { [weak self] samples in self?.receive(samples) }
        source.onStatus = { [weak self] status in
            guard let self, self.status != status else { return }
            self.status = status
        }
        source.onEvent = { [weak self] message in self?.log(message) }
        if let simulated = source as? SimulatedTrackMotionSource {
            simulated.onFinished = { [weak self] in if self?.recording == true { self?.finishRecording() } }
        }
        source.refreshStatus()
    }
    func selectSource(_ kind: SourceKind) {
        guard !recording, kind != source.kind else { return }
        source.stop(); source.onSamples = nil; source.onStatus = nil; source.onEvent = nil
        source = kind == .airPods ? AirPodsMotionSource() : SimulatedTrackMotionSource()
        selectedSource = kind
        clearBuffer(); latest = nil; receivedAt = nil; sampleAge = nil; sampleCount = 0
        restoreCalibration()
        attachSource()
        log("Source changed to \(kind.rawValue); saved AirPod mounting profiles retained.")
    }
    func recordSimulation() {
        guard !recording else { return }
        do {
            let metadata = try preparedMetadata()
            selectSource(.simulation)
            guard let simulated = source as? SimulatedTrackMotionSource else { return }
            // The simulator still needs a physical fixture. Unknown H is withheld
            // from reconstruction and stays nil in the saved run.
            simulated.configure(drop:metadata.verticalDrop ?? RunMetadata.defaultHeightMeters,includeJump:simulationIncludesJump,variation:Double(runs.count%3)-1,profile:simulationProfile)
            calibration = simulated.fixture.calibration
            clearBuffer(); latest = nil; receivedAt = nil; sampleAge = nil; sampleCount = 0
            try recorder.start(metadata:metadata,source:.simulation,calibration:calibration)
            recording = true; recordedCount = 0; recordingDuration = 0
            simulated.start()
            log("Recording explicit simulation through the shared recorder. Synthetic mounting calibration applied.")
        } catch { errorMessage = error.localizedDescription }
    }
    func stopMotion() {
        cancelCapture()
        if recording { finishRecording(reason:"Motion stopped manually.") }
        source.stop()
    }
    func shutdown() {
        timer?.invalidate(); timer = nil
        cancelCapture()
        if recording { finishRecording(reason:"Application closed; saved all received samples.") }
        cancelAnalyses()
        source.stop()
    }
    func clearBuffer() {
        cancelCapture(); buffer.clear(); history = []; statistics = SampleStatistics(samples:[])
        deliveryMonitor = MotionDeliveryMonitor(); uiDeliveryDelay = nil
        longestUIWait = 0; invalidSampleCount = 0
        liveMotion.update(nil)
        objectWillChange.send()
    }
    private func receive(_ deliveries: [MotionDelivery]) {
        isReceivingMotion = true
        defer { isReceivingMotion = false }
        var previous = latest
        var newest: MotionDelivery?
        for delivery in deliveries {
            let sample = delivery.sample
            guard sample.isValid else {
                invalidSampleCount += 1
                if invalidSampleCount == 1 { log("Invalid motion sample rejected. See Copy diagnostics for counts.") }
                continue
            }
            if let previous, previous.sensorLocation != sample.sensorLocation {
                if recording { finishRecording(reason:"Streaming bud changed. Recording ended before mixing sensors.") }
                restoreCalibration(); clearBuffer()
                log("Sensor location changed; unfinished poses cleared. Saved Left and Right mounting profiles retained.")
            }
            guard deliveryMonitor.append(delivery) else {
                if deliveryMonitor.rejectedTimestamps == 1 {
                    log("Repeated or backwards source timestamp rejected. Retry the connection if source time has restarted.")
                }
                continue
            }
            previous = sample; newest = delivery
            sampleCount += 1; buffer.append(sample)
            if recording {
                guard sourceKind == .simulation || sample.sensorLocation == selectedBud.location else {
                    finishRecording(reason:"The selected \(selectedBud.rawValue.lowercased()) AirPod is no longer the motion source.")
                    continue
                }
                do { try recorder.append(sample) }
                catch { finishRecording(reason:error.localizedDescription) }
            }
        }
        guard let newest else { return }
        // Every accepted sample reached the recorder; only the newest drives UI.
        latest = newest.sample
        receivedAt = newest.receivedAt
        let now = ProcessInfo.processInfo.systemUptime
        if let oldest = deliveries.first {
            longestUIWait = max(longestUIWait,max(0,now-oldest.receivedAt))
        }
        sampleAge = max(0,now-newest.receivedAt)
        uiDeliveryDelay = sampleAge
        liveMotion.update(newest.sample)
    }
    private func tick() {
        objectWillChange.send()
        sampleAge = receivedAt.map { max(0,ProcessInfo.processInfo.systemUptime-$0) }
        let samples = buffer.samples
        if !isDashboardPaused { history = samples }
        statistics = SampleStatistics(samples: Array(samples.suffix(100)))
        source.refreshStatus()
        retryCapture()
        if recording {
            recordedCount = recorder.session?.samples.count ?? 0
            recordingDuration = recorder.session?.duration ?? 0
            if let sampleAge, sampleAge > 1 { finishRecording(reason:"Motion stopped arriving for more than one second.") }
        }
    }
    var selectedRun: RunSession? { runs.first { $0.id == selectedRunID } }
    var comparisonRuns: [RunSession] { runs.filter { comparedRunIDs.contains($0.id) } }
    var readyComparisonRuns: [RunSession] { runs.filter { analyses[$0.id] != nil } }
    func prepareComparison() {
        // Check the library before offering selection. A saved raw recording is not
        // necessarily a reconstructable path, and must not count as a visible track.
        runs.forEach { ensureAnalysis($0) }
    }
    func setCompared(_ run: RunSession, selected: Bool) {
        if selected {
            guard runs.contains(where:{$0.id == run.id}), analyses[run.id] != nil,
                  !comparedRunIDs.contains(run.id), comparedRunIDs.count<4 else { return }
            let used = Set(comparisonColors.values)
            comparisonColors[run.id] = (0..<4).first { !used.contains($0) } ?? 0
            comparedRunIDs.insert(run.id)
        } else {
            comparedRunIDs.remove(run.id); comparisonColors[run.id] = nil
        }
        comparisonNotice = nil
    }
    func clearComparison() {
        comparedRunIDs = []; comparisonColors = [:]; comparisonNotice = nil
    }
    func compareLatestRuns() {
        clearComparison()
        readyComparisonRuns.prefix(2).forEach { setCompared($0,selected:true) }
    }
    func openComparison(including run: RunSession? = nil) {
        prepareComparison()
        if let run {
            if comparedRunIDs.count == 4 && !comparedRunIDs.contains(run.id) {
                comparisonNotice = "Four runs are selected. Remove one to add \(run.carDisplayName)."
            } else if analyses[run.id] != nil {
                setCompared(run,selected:true)
            }
        }
        area = .compare
    }
    func openRun(_ run: RunSession, in destination: AppArea = .track) {
        selectedRunID = run.id; ensureAnalysis(run); area = destination
    }
    var hasFreshMotion: Bool {
        latest != nil && (sampleAge ?? .infinity) < 1 && status.active && status.motionError == nil && !hasDeliveryBacklog
    }
    var hasDeliveryBacklog: Bool { sourceKind == .airPods && deliveryMonitor.extraLag >= 1 }
    var motionTimingSummary: String {
        let age = sampleAge.map { String(format:"%.0f ms",$0*1000) } ?? "—"
        let lag = String(format:"%.0f ms",deliveryMonitor.extraLag*1000)
        return "Last callback: \(age) ago · extra delivery lag: \(lag)"
    }
    var hasFreshSelectedMotion: Bool {
        hasFreshMotion && (sourceKind == .simulation || latest?.sensorLocation == selectedBud.location)
    }
    var connectionDiagnosticReport: String {
        let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "—"
        let recentEvents = events.prefix(15).reversed().map { "\($0.date.ISO8601Format())  \($0.message)" }.joined(separator:"\n")
        return """
        PodTrack \(version) (\(build)) · connection diagnostics
        \(ProcessInfo.processInfo.operatingSystemVersionString)
        Source: \(sourceKind.rawValue)
        Required side: \(selectedBud.rawValue.lowercased())
        Last sample side: \(latest?.sensorLocation.rawValue ?? "none")
        Motion authorization: \(status.authorization)
        Connection confirmed: \(status.connected)
        Motion available: \(status.available)
        Motion requested: \(status.requested)
        Motion API active: \(status.active)
        Accepted samples: \(sampleCount)
        Invalid samples rejected: \(invalidSampleCount)
        Repeated / old timestamps: \(deliveryMonitor.rejectedTimestamps)
        Waiting for first valid sample: \(status.waitingSeconds) s
        \(motionTimingSummary)
        Core Motion error: \(status.motionError ?? "none reported")
        Status: \(status.detail)

        Recent events:
        \(recentEvents)
        """
    }
    var headphoneLinkState: HeadphoneLinkState {
        if sourceKind == .simulation { return .simulation }
        if status.authorization == "Denied" || status.authorization == "Restricted" { return .permissionBlocked }
        if !status.requested && !status.active { return .idle }
        if status.motionError != nil { return .motionError }
        if hasFreshMotion {
            if latest?.sensorLocation == .unknown { return .unidentified }
            return hasFreshSelectedMotion ? .receiving : .wrongBud
        }
        if status.noMotionTimedOut { return .noMotion }
        if !status.connected { return .searching }
        return latest == nil ? .waitingForMotion : .stale
    }
    private func requireSelectedMotion() throws {
        guard !hasDeliveryBacklog else {
            throw PodTrackError.invalid("Motion is arriving late. Retry connection, then recapture level before calibrating.")
        }
        guard hasFreshMotion else { throw PodTrackError.invalid("Connect AirPods and wait for fresh motion samples first.") }
        guard hasFreshSelectedMotion else {
            let actual = latest?.sensorLocation.rawValue ?? "unknown"
            throw PodTrackError.invalid("Selected: \(selectedBud.rawValue) AirPod. macOS is sending: \(actual). Wait for the selected AirPod, or change the Right / Left selector to match the bud on the car.")
        }
    }
    func cancelCapture() {
        pendingCapture = nil
        captureStatus = nil
        lastCaptureIssue = nil
    }
    func captureLevelPose() { beginCapture(nose:false) }
    func captureNosePose() { beginCapture(nose:true) }
    private func beginCapture(nose: Bool) {
        guard !recording, pendingCapture == nil else { return }
        guard !nose || hasLevelPose else {
            errorMessage = "Capture the level pose first."
            return
        }
        // Drain callbacks that already arrived before establishing the boundary.
        source.flushPendingSamples()
        errorMessage = nil
        lastCaptureIssue = nil
        pendingCapture = (nose, ProcessInfo.processInfo.systemUptime + 6, latest?.timestamp)
        retryCapture()
    }
    func retryCapture(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard let pending = pendingCapture else { return }
        guard !recording else { cancelCapture(); return }
        guard now < pending.deadline else {
            let reason = lastCaptureIssue ?? "Keep the car steady while fresh motion is streaming."
            cancelCapture()
            errorMessage = "Capture timed out. " + reason
            return
        }
        do {
            try requireSelectedMotion()
            let pose = recentPose().filter { $0.timestamp > (pending.afterTimestamp ?? -.infinity) }
            try MountCalibration.checkSteady(pose)
            let captured = pending.nose
                ? try MountCalibration.capture(level:levelPose,noseUp:pose,source:sourceKind)
                : nil
            // Retry sensor/pose validation, but never retry a disk operation.
            cancelCapture()
            if let captured {
                calibration = captured; levelPose = []; hasLevelPose = false
                if sourceKind == .airPods {
                    calibrationProfiles[selectedBud.location] = captured
                    saveCalibration(for:selectedBud.location)
                } else { log("Synthetic mounting calibration captured.") }
            } else {
                if sourceKind == .airPods { try discardCalibration(for:selectedBud.location) }
                levelPose = pose; hasLevelPose = true; calibration = nil
                log("\(recordingSourceLabel) level pose captured. Raise the car nose without rolling sideways.")
            }
        } catch {
            if pendingCapture != nil, now < pending.deadline {
                lastCaptureIssue = error.localizedDescription
                captureStatus = "Hold still · trying again (\(Int(ceil(pending.deadline-now)))s). \(error.localizedDescription)"
            } else {
                cancelCapture()
                errorMessage = error.localizedDescription
            }
        }
    }
    var savedLevelGravity: Vector3? {
        guard hasLevelPose, !levelPose.isEmpty else { return nil }
        return MountCalibration.meanGravity(levelPose)
    }
    var liveCalibrationGravity: Vector3? {
        guard hasFreshSelectedMotion else { return nil }
        return latest?.gravity.normalized
    }
    var calibrationTiltDegrees: Double? {
        guard let saved = savedLevelGravity, let live = liveCalibrationGravity else { return nil }
        return acos(min(1,max(-1,saved.dot(live)))) * 180 / .pi
    }
    var calibrationAttitudeChangeDegrees: Double? {
        guard hasFreshSelectedMotion, let reference = levelPose.last?.attitude.normalized,
              let current = latest?.attitude.normalized else { return nil }
        let dot = reference.x*current.x + reference.y*current.y + reference.z*current.z + reference.w*current.w
        return 2 * acos(min(1,abs(dot))) * 180 / .pi
    }
    var calibrationFeedback: String {
        if hasDeliveryBacklog { return "Delayed motion. Retry connection and capture level again." }
        guard hasFreshSelectedMotion else { return "Waiting for fresh motion from the selected AirPod." }
        let pose = recentPose()
        var details = ""
        if hasLevelPose, !pose.isEmpty {
            let levelGravity = MountCalibration.meanGravity(levelPose)
            let currentGravity = MountCalibration.meanGravity(pose)
            let angle = acos(min(1,max(-1,levelGravity.dot(currentGravity)))) * 180 / .pi
            details = String(format:"Capture window (0.6 s): %.1f° · aim for 15–45°. ",angle)
        }
        do {
            try MountCalibration.checkSteady(pose)
            return details + "Pose is steady."
        } catch {
            return details + error.localizedDescription
        }
    }
    private func recentPose() -> [MotionSample] {
        buffer.recent(seconds:MountCalibration.poseWindowDuration)
    }
    func preparedMetadata() throws -> RunMetadata {
        var metadata = setup
        if heightIsKnown {
            guard let cm = Double(dropCentimeters.replacingOccurrences(of:",",with:".")) else { throw PodTrackError.invalid("Enter height H in centimetres, or choose Unknown.") }
            metadata.verticalDrop = cm/100
        }
        if knownLengthCentimeters.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { metadata.knownTrackLength = nil }
        else if let cm = Double(knownLengthCentimeters.replacingOccurrences(of:",",with:".")) { metadata.knownTrackLength = cm/100 }
        else { throw PodTrackError.invalid("Enter a valid known track length, or leave it blank.") }
        try metadata.validate()
        return metadata
    }
    func startRecording() {
        guard pendingCapture == nil else { return }
        source.flushPendingSamples()
        do {
            try requireSelectedMotion()
            guard hasMatchingCalibration || recordRawOnly else { throw PodTrackError.invalid("Calibrate the \(recordingSourceLabel) mounting first, or choose raw-only recording.") }
            if !recordRawOnly, let calibration {
                guard calibration.source == sourceKind, calibration.sensorLocation == latest?.sensorLocation else {
                    throw PodTrackError.invalid("The mounting calibration belongs to a different source or AirPod. Calibrate the selected bud again.")
                }
            }
            try recorder.start(metadata:preparedMetadata(),source:sourceKind,calibration:recordRawOnly ? nil : calibration)
            recording = true; recordedCount = 0; recordingDuration = 0
            log("Recording started · \(recordingSourceLabel). Hold still briefly, then release the car.")
        } catch { errorMessage = error.localizedDescription }
    }
    func finishRecording(reason: String? = nil) {
        if !isReceivingMotion { source.flushPendingSamples() }
        guard let session = recorder.finish(reason:reason) else { return }
        recording = false; recordedCount = session.samples.count; recordingDuration = session.duration
        if let reason { log(reason) }
        guard !session.samples.isEmpty else { log("Recording ended without samples; no empty run saved."); return }
        runs.insert(session,at:0); selectedRunID = session.id
        persist(session)
        log("Recorded \(session.samples.count) samples · \(session.carDisplayName).")
        selectReconstructionMethod(.improved)
        ensureAnalysis(session)
        area = .analysis
    }
    func persist(_ session: RunSession) {
        do { try store.save(session); unsavedIDs.remove(session.id) }
        catch { unsavedIDs.insert(session.id); errorMessage = "Run remains in memory, but could not be saved: \(error.localizedDescription). Use Retry save or export before closing." }
    }
    func exportBuffer() {
        let origin = RecordingOrigin.identify(source:sourceKind,samples:history)
        SaveExporter.save(text:CSVExporter.rawSamples(buffer.samples,source:sourceKind,calibration:calibration),name:"PodTrack-\(origin.rawValue)-live.csv",json:false) { errorMessage = $0 }
    }
    func exportRaw(_ session: RunSession) { SaveExporter.save(text:CSVExporter.rawRun(session),name:"\(session.exportBasename)-raw.csv",json:false) { errorMessage = $0 } }
    var selectedAnalysis: AnalysisResult? { selectedRunID.flatMap { analyses[$0] } }

    func selectReconstructionMethod(_ method: ReconstructionMethod) {
        guard reconstructionMethod != method else { return }
        cancelAnalyses()
        reconstructionMethod = method
        analyses = analysisCache[method] ?? [:]; analysisErrors = errorCache[method] ?? [:]
        cursorTime = 0; rulerSelection = .init(); comparisonNotice = nil
        // Retain comparison selections while the requested method is being computed.
        // No old-method geometry may be displayed under the new method's label.
        for run in comparisonRuns where analysisErrors[run.id] != nil { removeFailedComparison(run) }
        if area == .compare || area == .export { prepareComparison() }
        else {
            comparisonRuns.forEach { ensureAnalysis($0) }
            if let run = selectedRun { ensureAnalysis(run) }
        }
    }

    private func cancelAnalyses() {
        analysisTasks.values.forEach { $0.task.cancel() }
        analysisTasks = [:]; analysingIDs = []
    }

    private func invalidateAnalysis(_ id: UUID) {
        analysisTasks[id]?.task.cancel(); analysisTasks[id] = nil; analysingIDs.remove(id)
        analyses[id] = nil; analysisErrors[id] = nil
        for method in ReconstructionMethod.allCases { analysisCache[method]?[id] = nil; errorCache[method]?[id] = nil }
    }

    private func removeFailedComparison(_ run: RunSession) {
        guard comparedRunIDs.contains(run.id) else { return }
        setCompared(run,selected:false)
        comparisonNotice = "\(run.carDisplayName) has no \(reconstructionMethod.rawValue) reconstruction. Its recording is still saved; you can select the other method."
    }

    func ensureAnalysis(_ run: RunSession) {
        guard runs.contains(where:{$0 == run}), analyses[run.id] == nil,
              analysisErrors[run.id] == nil, !analysingIDs.contains(run.id) else { return }
        let method = reconstructionMethod, token = UUID()
        analysingIDs.insert(run.id)
        let task = Task { [weak self] in
            let worker = Task.detached(priority:.userInitiated) { try method.analyze(run) }
            let outcome = await withTaskCancellationHandler(operation:{ await worker.result },onCancel:{ worker.cancel() })
            guard !Task.isCancelled, let self, analysisTasks[run.id]?.token == token,
                  reconstructionMethod == method, runs.first(where:{$0.id == run.id}) == run else { return }
            switch outcome {
            case .success(let result):
                analyses[run.id] = result; analysisCache[method,default:[:]][run.id] = result
            case .failure(let error):
                analysisErrors[run.id] = error.localizedDescription
                errorCache[method,default:[:]][run.id] = error.localizedDescription
                removeFailedComparison(run)
            }
            analysingIDs.remove(run.id); analysisTasks[run.id] = nil
            PrototypeVerification.reportLibraryWindowIfRequested(model:self)
        }
        analysisTasks[run.id] = (token,task)
    }
    func updateRun(_ run: RunSession) {
        guard let index = runs.firstIndex(where:{$0.id == run.id}) else { return }
        runs[index] = run; persist(run)
        invalidateAnalysis(run.id)
        ensureAnalysis(run)
    }

    func reloadDeletedRuns() {
        do {
            let loaded = try store.loadRecentlyDeleted()
            deletedRuns = loaded.runs
            loaded.warnings.forEach { log($0) }
            if !loaded.warnings.isEmpty { errorMessage = loaded.warnings.joined(separator:"\n") }
        } catch { errorMessage = "Could not read Recently Deleted: \(error.localizedDescription)" }
    }

    func deleteRecording(_ run: RunSession) {
        guard let index = runs.firstIndex(where:{$0.id == run.id}) else { return }
        let current = runs[index]
        do {
            try store.moveToRecentlyDeleted(current)
            invalidateAnalysis(current.id)
            setCompared(current,selected:false)
            runs.remove(at:index); unsavedIDs.remove(current.id)
            deletedRuns.removeAll { $0.id == current.id }; deletedRuns.insert(current,at:0)
            lastDeletedRunID = current.id
            if selectedRunID == current.id {
                selectedRunID = runs.isEmpty ? nil : runs[min(index,runs.count-1)].id
                if let next = selectedRun { ensureAnalysis(next) }
            }
        } catch { errorMessage = "Recording was not removed: \(error.localizedDescription)" }
    }

    func restoreRecording(_ run: RunSession) {
        guard deletedRuns.contains(where:{$0.id == run.id}), !runs.contains(where:{$0.id == run.id}) else { return }
        do {
            try store.restore(run.id)
            runs.append(run); runs.sort { $0.createdAt>$1.createdAt }
            deletedRuns.removeAll { $0.id == run.id }
            if lastDeletedRunID == run.id { lastDeletedRunID = nil }
            if selectedRunID == nil { selectedRunID = run.id }
            ensureAnalysis(run)
        } catch { errorMessage = "Recording could not be restored: \(error.localizedDescription)" }
    }
    func exportTrack(_ run: RunSession) {
        guard let result = analyses[run.id] else { return }
        SaveExporter.save(text:CSVExporter.reconstructedTrack(result),name:"\(run.exportBasename)-\(reconstructionMethod.rawValue.lowercased())-estimated-track.csv",json:false) { errorMessage = $0 }
    }
    func exportMetrics(_ run: RunSession) {
        guard let result = analyses[run.id] else { return }
        do { SaveExporter.save(text:try CSVExporter.processedJSON(run:run,result:result),name:"\(run.exportBasename)-\(reconstructionMethod.rawValue.lowercased())-analysis.json",json:true) { errorMessage = $0 } }
        catch { errorMessage = error.localizedDescription }
    }
    func log(_ message: String) {
        events.insert(.init(message: message), at: 0)
        if events.count > 200 { events.removeLast(events.count - 200) }
    }
}
