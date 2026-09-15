import SwiftUI
import PodTrackCore

struct RunEditSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State var run: RunSession
    @State private var drop = ""
    @State private var length = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Edit saved run").font(.title2.bold())
            Text("Raw motion and the original mounting calibration stay attached to this run. Changing a constraint recomputes its estimates.").foregroundStyle(.secondary)
            LabeledContent("Recorded with",value:run.recordedOrigin.label).font(.headline)
            LabeledContent("Track name") { TextField("Track name",text:$run.metadata.trackName) }
            LabeledContent("Car name") { TextField("Car name",text:$run.metadata.carName) }
            HeightKnowledgePicker(isKnown:Binding(get:{run.metadata.verticalDrop != nil},set:{run.metadata.verticalDrop = $0 ? RunMetadata.defaultHeightMeters : nil}))
            if run.metadata.verticalDrop != nil {
            LabeledContent("Height H (cm)") {
                HStack(spacing:6) { TextField("58",text:$drop); HeightStepper(text:$drop) }
            }
            Picker("Height meaning",selection:Binding(get:{run.metadata.resolvedHeightConstraint},set:{run.metadata.heightConstraint = $0})) {
                ForEach(HeightConstraint.allCases,id:\.self) { Text($0.label).tag($0) }
            }
            Text("Lowest-to-highest mode sets ground at 0 and the highest point at H, even when the finish is elevated.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Without a measured height or length, the whole path = 1 relative unit (u). Add either measurement later to set scale.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("Known along-track length (cm)") { TextField("Optional",text:$length) }
            Text("Measure along the entire driven track, from start to finish. This adds a scale constraint; it cannot correct a wrong mounting direction or missing motion.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Notes",text:$run.metadata.notes,axis:.vertical).lineLimit(2...5)
            LabeledContent("Smoothing (s)") { Slider(value:$run.metadata.settings.smoothingSeconds,in:0...0.5) }
            Picker("Acceleration sign",selection:$run.metadata.settings.accelerationPolarity) {
                ForEach(AccelerationPolarity.allCases,id:\.self) { Text($0.rawValue).tag($0) }
            }
            Toggle("Start and end at rest",isOn:$run.metadata.settings.startsAndEndsAtRest)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save & reconstruct") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.textFieldStyle(.roundedBorder).padding(28).frame(width:520)
            .onAppear { drop = formatted((run.metadata.verticalDrop ?? RunMetadata.defaultHeightMeters)*100); length = run.metadata.knownTrackLength.map { formatted($0*100) } ?? "" }
    }
    private func save() {
        do {
            if run.metadata.verticalDrop != nil {
                guard let cm = Double(drop.replacingOccurrences(of:",",with:".")) else { throw PodTrackError.invalid("Enter a valid height H, or choose Unknown.") }
                run.metadata.verticalDrop = cm/100
            }
            if length.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { run.metadata.knownTrackLength = nil }
            else if let cm = Double(length.replacingOccurrences(of:",",with:".")) { run.metadata.knownTrackLength = cm/100 }
            else { throw PodTrackError.invalid("Enter a valid track length, or leave it empty.") }
            try run.metadata.validate(); model.updateRun(run); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
